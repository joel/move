# frozen_string_literal: true

# Subdomain tenancy configuration (Phase D1).
#
# The apex host serves auth + onboarding; Organizations live on sibling
# subdomains under the registrable domain (`<slug>.workeverywhere.docker`), so a
# single-label wildcard cert/DNS covers them and the apex shares a session cookie
# with them. WebAuthn/passkeys stay bound to the apex — no re-registration.
app_host = ENV.fetch("APP_HOST", "move.workeverywhere.docker")
Rails.application.config.x.app_host = app_host

# Base domain that org subdomains hang off — the apex host minus its first label
# (move.workeverywhere.docker → workeverywhere.docker). Override with TENANT_DOMAIN.
tenant_domain = ENV.fetch("TENANT_DOMAIN") { app_host.split(".", 2).last }
Rails.application.config.x.tenant_domain = tenant_domain

# Share the session across the apex and org subdomains. Skipped in test, where
# Capybara/rack-test serve from a different host and a fixed cookie domain would
# break session persistence.
unless Rails.env.test?
  Rails.application.config.session_store :cookie_store,
                                         key: "_move_session",
                                         domain: ".#{tenant_domain}",
                                         same_site: :lax
end
