# Security model & threat model

This document is the **source of truth for Move's security posture**: the trust
boundaries, the assets we protect and the control enforcing each, a per-class
review checklist (with file pointers), and the risks we have consciously accepted.

It is **open source**, which is itself a threat-model assumption: assume an
attacker has full read access to this repository and can point an AI at it to hunt
for exploitable weaknesses. Our defence is twofold:

- a **per-change** security pass — [`/execution-plan`](../../.claude/skills/execution-plan/SKILL.md)
  **Step 5d** runs the `/security-review` skill on every security-sensitive branch
  diff *before* the PR is public; and
- a **periodic** whole-repo adversarial scan —
  [`.github/workflows/security-audit.yml`](../../.github/workflows/security-audit.yml)
  (`Security Audit`) runs **on demand** (manual `workflow_dispatch`; the weekly
  schedule is paused until #430 hardens the public-log residual) and, on findings, opens a
  fixed-body `security`-labelled issue and fails the run. **It never republishes the
  model's report** to any sink it controls (summary/artifact/issue) — those emit
  only a fixed, content-free notice — because prompt compliance is not an
  enforcement boundary. The audit prompt is additionally constrained to
  non-sensitive output to mitigate the one residual we cannot redact: the Codex
  action echoes its own output to the public Actions log. The **actionable** detail
  is the job of the per-change `/security-review` pass (Step 5d) and a maintainer's
  local audit re-run — never this public CI report. (Tracked hardening: route full
  detail through a private channel / suppress the action's stdout.)

Both apply the **"Security & data"** section of
[`.github/codex/review-rubric.md`](../../.github/codex/review-rubric.md), which
mirrors the checklist below.

---

## Trust boundaries

```mermaid
flowchart TB
    attacker([Anonymous internet]):::ext

    subgraph edge["Cloudflare edge (TLS, WAF, wildcard cert)"]
        cf["Cloudflare Tunnel → cloudflared → kamal-proxy (HTTP)"]
    end

    attacker -->|HTTPS| edge

    subgraph app["Rails app (single image, all tenants)"]
        apex["Apex host move-easy.org<br/>(broker only: login, org registry,<br/>session handoff)"]
        elevator{{"Apartment elevator<br/>resolves tenant from subdomain<br/>unknown ⇒ 404"}}
        sub["Org subdomain slug.move-easy.org<br/>(authenticated session lives here)"]
        mcp["POST /mcp + /mcp/uploads<br/>(per-Move Bearer token)"]
    end

    cf --> apex
    cf --> elevator
    elevator --> sub
    cf --> mcp

    subgraph pg["PostgreSQL 18 — schema-per-tenant"]
        public[("public schema<br/>Rodauth auth tables +<br/>Organization registry")]:::trust
        tenant[("tenant schema per Org<br/>Move / Box / Item / Media")]:::trust
    end

    apex --> public
    sub --> tenant
    mcp --> tenant
    elevator -. excluded_models .-> public

    subgraph egress["External egress boundary"]
        ai["AI providers (OpenAI / Gemini / Anthropic)<br/>per-Move BYO keys, encrypted at rest"]:::ext
        storage["SeaweedFS / object storage<br/>(per-tenant media)"]
    end

    tenant -->|user text + images| ai
    tenant --> storage

    classDef ext fill:#7f1d1d,color:#fff,stroke:#fca5a5;
    classDef trust fill:#14532d,color:#fff,stroke:#86efac;
```

The headline boundaries an attacker probes:

1. **Apex vs org-subdomain.** The apex (`move.<zone>` locally, `move-easy.org` in
   prod) is **broker-only** — login, the org registry, and single-use session
   handoff. An authenticated session is established and lingers **only** on the org
   subdomain, never the apex. Cookies are host-only.
2. **`public` schema vs tenant schema.** Each Organization is a PostgreSQL
   **schema**. Auth (Rodauth) tables and the Organization registry live in `public`
   via Apartment `excluded_models`; everything Move-scoped lives in the tenant
   schema. The elevator picks the schema **per request** from the subdomain.
3. **Per-Move MCP Bearer token.** `POST /mcp` and `/mcp/uploads` are authenticated
   by a per-Move integration token (stored as a digest, never raw) that resolves a
   single Move *within* the subdomain's tenant. The Move-scoped `signed_id` means
   only the issuing token can attach an upload.
4. **External egress.** User text and images are sent to external AI providers for
   recognition/embedding. This is a one-way **data-egress** boundary: per-Move BYO
   keys, encrypted at rest, no secret/PII leakage.

---

## Assets & controls

| Asset | Threat | Control | Where it lives |
|---|---|---|---|
| Other tenants' data | Cross-tenant read/write | Apartment schema-per-tenant + per-request elevator; unknown subdomain ⇒ 404 (no disclosure) | `config/initializers/apartment.rb`, `config/initializers/apartment_elevator.rb` (`EXCLUDED_SUBDOMAINS = %w[move mail storage bucket www]`) |
| Auth / account tables | Empty-tenant-clone footgun, cross-tenant auth | `excluded_models` + `persistent_schemas %w[public]`; schema-qualify auth SQL to `public.` | `config/initializers/apartment.rb`, `app/misc/` |
| Per-resource access | IDOR / privilege escalation | ActionPolicy `authorize` on every action + `authorized_scope` for row visibility; membership gate | `app/policies/` (`*_policy.rb`, `concerns/move_membership_authorization.rb`) |
| Domain invariants | Forged param / stale form / direct MCP call | Phase/state + ownership guards in the **shared action**, gating on the validated result | `app/actions/` |
| Sessions | Hijack, fixation, cross-host leak | Passwordless Rodauth; verify-before-login; host-only cookies; single-use `SessionHandoffToken`; remember-me scoped to subdomain | `app/misc/`, `app/jobs/purge_stale_session_handoff_tokens_job.rb` |
| API keys / secrets | Leakage | Encrypted per-Move attributes; Doppler / Rails credentials only; nothing in code or logs | `app/models/` (encrypted attrs), Doppler `move/prd` |
| Uploaded media | Malicious upload, oversized payload, attach-others' | Magic-byte sniff (`image/*`) + size cap (`Media::MAX_IMAGE_BYTES`) + Move-scoped `signed_id`; transcode-on-attach | `app/controllers/mcp_uploads_controller.rb`, `app/services/image_normalizer.rb` |
| MCP endpoints | Token theft / cross-Move | Per-Move Bearer (digest-stored), resolved within tenant; every tool reuses an authorized `app/actions` call; `mcp.tool_called` audit events | `app/mcp/` |

---

## Per-class review checklist

The classes the per-change pass (Step 5d) and the scheduled audit work through —
each with where the control lives, so a finding can be traced to code:

- **Tenant isolation** — queries resolve in the right schema; AR lookups after an
  `Apartment::Tenant.switch` block are re-wrapped; signed Turbo Stream names derive
  from a tenant-unique uuid (that signed name **is** the channel auth); no
  `default_scope` widening leaks other-tenant/soft-deleted rows. → `config/initializers/apartment*.rb`, ActionCable `turbo_stream_from` sites.
- **Authorization / IDOR** — `authorize` + `authorized_scope` everywhere;
  selection-only vocabulary rejects out-of-Move ids; ownership/phase guards in the
  action, gating on the validated result not the raw param. → `app/policies/`, `app/actions/`.
- **Authentication** — no Rodauth bypass; verify-before-login; status checks;
  remember-me on subdomain only; single-use handoff tokens; WebAuthn RP id = apex;
  social sign-in respects account-creation guards. → `app/misc/`.
- **Injection & input** — strong-params re-sliced inside the action; no `Arel.sql`
  string interpolation; no new shell/command injection. → `app/actions/`, `app/controllers/`.
- **Upload & egress** — magic-byte sniff + size cap + Move-scoped signed-id;
  external AI calls leak no secret/PII; BYO keys encrypted. → `app/services/image_normalizer.rb`, `app/services/recognition_providers/`, `app/services/embedding_providers/`.
- **Secrets** — none in code/fixtures/logs; encrypted attrs; Doppler/credentials.
- **Output safety** — audit `raw`/`html_safe`/`sanitize` for XSS; Rodauth forms
  carry context via hidden fields; Prawn user text uses a Unicode TTF. → Phlex views, `app/misc/` Rodauth views.

---

## Accepted risks

- **5 dev-only command-injection warnings** in `config/brakeman.ignore`
  (`bin/cli-files/**` — `system("docker …")`). Accepted because `bin/cli` is local
  developer tooling: the interpolated values come from project config, not user
  input, and the code is **never reachable from a web request**. New `system(...)`
  with interpolation outside `bin/cli` is **not** covered by this acceptance and
  must be flagged.

- **Active Storage blob bytes are not tenant-isolated; delivery relies on
  signed-id secrecy, not membership authorization.** `ActiveStorage::Blob`,
  `Attachment`, and `VariantRecord` are Apartment-**excluded** and live in the
  shared `public` schema (`config/initializers/apartment.rb`) — deliberately, so
  Rails 8.1's Active Storage proxy (which leases a fresh pool connection that
  Apartment resets to `public`) can resolve them regardless of the active tenant.
  Files are served via `rails_storage_proxy` URLs, and the default proxy
  controller performs **no** authorization beyond validating the (non-expiring)
  signed id. So while the domain `Media` row is per-tenant, the file it points to
  is **not** — anyone holding a valid proxy URL can fetch that blob without an
  Organization/Move membership check. Accepted because: (a) proxy signed ids are
  unguessable (HMAC over the app secret), (b) the schema-per-tenant model still
  isolates every *domain* record and the `Media`→blob mapping, and (c) fronting
  blob delivery with a per-request membership check conflicts with the
  fresh-`public`-connection constraint above. **Residual risk:** a signed-id /
  proxy URL that leaks (shared link, server/CDN log, CDN cache) grants
  cross-tenant read of that single image with no membership gate — there is no
  second authorization layer behind the URL. Revisit if blob contents ever hold
  higher-sensitivity data than move-inventory photos, or wrap proxy delivery in an
  authorization check at that point. (Audit finding F5, 2026-07-02.)

---

## Related references

- [`.github/codex/review-rubric.md`](../../.github/codex/review-rubric.md) — the
  "Security & data" checklist applied by every review.
- [`architecture.md`](architecture.md) — runtime request flow + schema-per-tenant
  model (the non-adversarial counterpart to this doc).
- [`app/misc/AGENTS.md`](../../app/misc/AGENTS.md) — auth-layer gotchas.
- [`app/mcp/AGENTS.md`](../../app/mcp/AGENTS.md) — MCP token + upload handshake.
- CI static checks: Brakeman + bundle-audit in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml).

_Last updated: 2026-07-02 (added accepted risk: shared-schema Active Storage blob delivery — audit finding F5)._
