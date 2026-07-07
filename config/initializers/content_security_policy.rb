# frozen_string_literal: true

# Content Security Policy (#493), ENFORCING. Rolled out REPORT-ONLY first so a
# mis-scoped directive could not break a live surface — notably Google One Tap,
# which is prod-only (gated on GOOGLE_CLIENT_ID, loading
# https://accounts.google.com/gsi/client) and cannot be exercised in dev. Flipped to
# enforcing after prod ran violation-free (12h of traffic + an active browser pass
# over the apex, the sign-in page with gsi/client executing, an org subdomain, and
# create-account — zero [csp-violation] reports).
#
# `script-src` stays strict — `:self` + a per-request nonce, no `unsafe-inline` —
# which is the real XSS backstop. `style-src` allows `unsafe-inline` because the UI
# uses inline `style="width: N%"` (progress bars) and `style="display:none"`
# toggles; styles can't execute script, so this is the standard pragmatic trade-off.
Rails.application.configure do
  google_gsi = "https://accounts.google.com"
  # Only widen the policy for Google's SDK when Google sign-in is actually wired up
  # (mirrors how the UI gates the One Tap/OAuth affordances).
  google = ENV["GOOGLE_CLIENT_ID"].present? ? [google_gsi] : []

  # ActionCable (turbo_stream_from on the capture / label-print pages) connects to
  # wss://<host>/cable. `:self` is NOT honoured for WebSocket in every browser (older
  # Safari), so name the wss origins explicitly: the apex + every tenant subdomain of
  # the configured zone. Falls back to the wss scheme where the zone is unset (test).
  zone = Rails.application.config.x.tenant_zone.to_s.presence
  cable_origins = zone ? ["wss://#{zone}", "wss://*.#{zone}"] : ["wss:"]

  # In prod, media <img> is served from the Cloudflare-edge transform Worker on a
  # distinct host (media.<zone>), so img-src must allow it. Unset in dev/test — the
  # master-proxy fallback is same-origin (:self), so the policy is unchanged there.
  # Read ENV directly (like GOOGLE_CLIENT_ID above), NOT config.x.media_transform_host:
  # this initializer sorts before media_transform.rb, so config.x isn't set yet here.
  media_host = ENV["MEDIA_TRANSFORM_HOST"].presence
  media_img = media_host ? ["https://#{media_host}"] : []

  # Active Storage Direct Upload (#572) PUTs the captured photo straight to R2's S3
  # endpoint via fetch/XHR, so connect-src must allow that origin. R2_ENDPOINT is
  # the account-scoped origin (https://<account-id>.r2.cloudflarestorage.com); unset
  # in dev/test (direct upload disabled there), so connect-src is unchanged.
  r2_origin = ENV["R2_ENDPOINT"].presence
  direct_upload_connect = r2_origin ? [r2_origin] : []

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src(:self, *google)                       # + nonce (below); no unsafe-inline
    policy.style_src(:self, :unsafe_inline, *google)        # inline style="…" attrs
    policy.img_src(:self, :data, :blob, *media_img, *google,
                   *(google.empty? ? [] : ["https://*.googleusercontent.com"]))
    policy.font_src :self, :data
    policy.connect_src(:self, *cable_origins, *google, *direct_upload_connect) # + wss + R2 direct upload
    policy.frame_src(*(google.empty? ? [:none] : google)) # One Tap iframe
    policy.object_src :none
    policy.base_uri :self
    # NB: form-action is intentionally omitted. The passwordless apex↔subdomain auth
    # flow submits forms across hosts (e.g. the email-auth form on the broker apex),
    # which `form-action 'self'` blocks; scoping it to the tenant zone is per-env and
    # not worth the fragility for a minor secondary control — the strict `script-src`
    # is the XSS backstop. Revisit if the auth flow stops crossing hosts.
    policy.frame_ancestors :none
    # Keep collecting violations while enforcing (CspReportsController logs them) —
    # ongoing telemetry for anything a future change breaks. Same-origin path —
    # resolves to the current host (apex or subdomain).
    policy.report_uri "/csp-violation-report"
  end

  # Per-request nonce for legitimate inline <script> (the theme-boot script and the
  # importmap tags). A fresh random value — not `session.id`, which is blank on a
  # logged-out request (no session yet) and would emit an empty, unmatchable nonce.
  # The per-request nonce lives in the rendered body, so the body-based etag varies
  # with it (no stale 304 serving an old nonce), and it never writes to the session.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Enforcing since the report-only rollout ran clean in prod (see header comment).
  config.content_security_policy_report_only = false
end
