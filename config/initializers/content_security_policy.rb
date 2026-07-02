# frozen_string_literal: true

# Content Security Policy (#493). Shipped REPORT-ONLY first: browsers evaluate the
# policy and report violations but do NOT block, so a mis-scoped directive cannot
# break a live surface — notably Google One Tap, which is prod-only (gated on
# GOOGLE_CLIENT_ID, loading https://accounts.google.com/gsi/client) and cannot be
# exercised in dev. Flip `content_security_policy_report_only` to false once prod is
# confirmed violation-free (especially the Google sign-in page). See DESIGN/AGENTS.
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

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src(:self, *google)                       # + nonce (below); no unsafe-inline
    policy.style_src(:self, :unsafe_inline, *google)        # inline style="…" attrs
    policy.img_src(:self, :data, :blob, *google, *(google.empty? ? [] : ["https://*.googleusercontent.com"]))
    policy.font_src :self, :data
    policy.connect_src(:self, *google)                      # ActionCable wss is same-origin (:self)
    policy.frame_src(*(google.empty? ? [:none] : google))   # One Tap iframe
    policy.object_src :none
    policy.base_uri :self
    # NB: form-action is intentionally omitted. The passwordless apex↔subdomain auth
    # flow submits forms across hosts (e.g. the email-auth form on the broker apex),
    # which `form-action 'self'` blocks; scoping it to the tenant zone is per-env and
    # not worth the fragility for a minor secondary control — the strict `script-src`
    # is the XSS backstop. Revisit if the auth flow stops crossing hosts.
    policy.frame_ancestors :none
  end

  # Per-request nonce for legitimate inline <script> (the theme-boot script and the
  # importmap tags). A fresh random value — not `session.id`, which is blank on a
  # logged-out request (no session yet) and would emit an empty, unmatchable nonce.
  # The per-request nonce lives in the rendered body, so the body-based etag varies
  # with it (no stale 304 serving an old nonce), and it never writes to the session.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Roll out REPORT-ONLY first (see header comment). Flip to false to enforce.
  config.content_security_policy_report_only = true
end
