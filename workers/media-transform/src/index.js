// Cloudflare Worker: edge media transformation (#572).
//
// Serves private, tenant-scoped Active Storage media through Cloudflare's edge
// image transforms, gated by a short-lived HMAC token minted by the Rails app
// (MediaVariants::TransformUrl). The R2 bucket stays private; the only access is
// a request carrying a currently-valid token.
//
//   URL:  /<size>/<blob_key>?t=<hex hmac>&exp=<unix>
//   token = HMAC-SHA256("<blob_key>|<size>|<exp>", MEDIA_TRANSFORM_SECRET)
//
// Bindings (wrangler.toml): env.MEDIA_BUCKET (R2), env.IMAGES (Images transform),
// env.MEDIA_TRANSFORM_SECRET (Worker secret — the SAME value Rails signs with).

// Keep in sync with MediaVariants::TransformUrl::SIZES in the Rails app. The
// Worker trusts the `size` path segment only AFTER the HMAC verifies, so a client
// can never request an arbitrary width — the billed transform set is bounded to
// exactly these. fit "scale-down" mirrors Active Storage's resize_to_limit:
// bounded on both axes, never upscaled, never cropped.
const SIZES = {
  thumb: { width: 400, height: 400, fit: "scale-down" },
  detail: { width: 1600, height: 1600, fit: "scale-down" },
};

// A successfully transformed image is immutable for its (key, size, format) — the
// master never changes in place — so cache it hard at the edge and in the browser.
const CACHE_CONTROL_SUCCESS = "public, max-age=31536000, immutable";

export default {
  async fetch(request, env, ctx) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return errorResponse(405, "Method not allowed");
    }

    const url = new URL(request.url);
    const match = /^\/(thumb|detail)\/([^/]+)$/.exec(url.pathname);
    if (!match) return errorResponse(400, "Bad request");

    const [, size, blobKey] = match;
    const transform = SIZES[size];

    const token = url.searchParams.get("t");
    const expParam = url.searchParams.get("exp");
    if (!token || !expParam) return errorResponse(403, "Missing token");

    const exp = Number.parseInt(expParam, 10);
    if (!Number.isFinite(exp)) return errorResponse(403, "Bad token");
    if (exp < Math.floor(Date.now() / 1000)) return errorResponse(403, "Token expired");

    // Missing secret binding is a deploy misconfiguration, not a client error —
    // surface it distinctly (500) rather than letting importKey throw an opaque
    // one, and NEVER let it read as an auth pass.
    if (!env.MEDIA_TRANSFORM_SECRET) return errorResponse(500, "Server misconfigured: no signing secret");

    const ok = await verifyToken(env.MEDIA_TRANSFORM_SECRET, blobKey, size, exp, token);
    if (!ok) return errorResponse(403, "Bad token");

    // Negotiate output format from Accept — Cloudflare bills each (source, size,
    // format) once, so this is a small ≤3× multiplier over the bounded size set.
    const format = negotiateFormat(request.headers.get("Accept"));

    // Normalized cache key: STRIP the short-lived t/exp (so every valid token for
    // the same key+size shares ONE cache entry) but KEEP the format (avif/webp/jpeg
    // are genuinely different bytes and must not collide).
    const cache = caches.default;
    const cacheKeyUrl = new URL(url);
    cacheKeyUrl.search = `?format=${format}`;
    const cacheKey = new Request(cacheKeyUrl.toString(), { method: "GET" });

    // The Cache API is invisible to `cf-cache-status` (that header only reflects
    // Cloudflare's HTTP cache), so expose HIT/MISS explicitly for observability.
    // The stored response carries MISS (set below, pre-put); rewrap hits so the
    // served copy reads HIT without mutating the shared cache entry.
    const cached = await cache.match(cacheKey);
    if (cached) {
      const hit = new Response(cached.body, cached);
      hit.headers.set("X-Media-Cache", "HIT");
      return hit;
    }

    let object;
    try {
      object = await env.MEDIA_BUCKET.get(blobKey);
    } catch {
      return errorResponse(502, "Storage read failed");
    }
    if (!object) return errorResponse(404, "Not found");

    let transformed;
    try {
      transformed = await env.IMAGES.input(object.body)
        .transform({ width: transform.width, height: transform.height, fit: transform.fit })
        .output({ format: `image/${format}` });
    } catch {
      return errorResponse(502, "Transform failed");
    }

    const out = transformed.response();
    const headers = new Headers(out.headers);
    headers.set("Cache-Control", CACHE_CONTROL_SUCCESS);
    headers.set("Vary", "Accept");
    headers.set("X-Media-Cache", "MISS");
    const response = new Response(out.body, { status: 200, headers });

    // Cache the transformed bytes (best-effort, per-colo) so a repeat view at this
    // edge skips the R2 GET + Images transform. waitUntil so the put never delays
    // the response.
    ctx.waitUntil(cache.put(cacheKey, response.clone()));
    return response;
  },
};

// Verify via WebCrypto's native HMAC verify, which recomputes AND compares in
// constant time — preferred over a hand-rolled recompute + string diff.
async function verifyToken(secret, blobKey, size, exp, hexToken) {
  const signature = hexToBytes(hexToken);
  if (!signature) return false;

  // Any crypto error (unexpected key/signature shape) must fail CLOSED — deny,
  // never throw an uncaught 500 that could read as a non-403.
  try {
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const message = new TextEncoder().encode(`${blobKey}|${size}|${exp}`);
    return await crypto.subtle.verify("HMAC", key, signature, message);
  } catch {
    return false;
  }
}

function hexToBytes(hex) {
  if (typeof hex !== "string" || hex.length % 2 !== 0 || !/^[0-9a-f]+$/i.test(hex)) return null;
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = Number.parseInt(hex.substr(i * 2, 2), 16);
  }
  return bytes;
}

function negotiateFormat(accept) {
  const header = accept || "";
  if (header.includes("image/avif")) return "avif";
  if (header.includes("image/webp")) return "webp";
  return "jpeg"; // universal fallback — matches the stored master's format
}

// Errors must NEVER be cached — a transient 404/403 pinned at the edge would
// outlive the fix (mirrors lib/middleware/active_storage_error_cache_guard.rb, #490).
function errorResponse(status, message) {
  return new Response(message, {
    status,
    headers: { "Content-Type": "text/plain", "Cache-Control": "no-store" },
  });
}
