# frozen_string_literal: true

# Subdomain tenancy configuration (Phase D1).
#
# The apex host serves auth + onboarding; Organizations live on
# `<slug>.<app_host>` subdomains. The session cookie is scoped to the parent
# domain so a login on the apex carries down to org subdomains (keeping
# WebAuthn/passkeys bound to the apex — no re-registration needed).
app_host = ENV.fetch("APP_HOST", "move.workeverywhere.docker")
Rails.application.config.x.app_host = app_host

# Share the session across the apex and its org subdomains. Skipped in test,
# where Capybara/rack-test serve from a different host and a fixed cookie
# domain would break session persistence.
unless Rails.env.test?
  Rails.application.config.session_store :cookie_store,
                                         key: "_move_session",
                                         domain: ".#{app_host}",
                                         same_site: :lax
end
