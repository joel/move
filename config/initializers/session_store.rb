# frozen_string_literal: true

# Share the session cookie across org subdomains so the apex login session
# carries to <slug>.<tenant_zone>. The domain is environment-configurable
# (config.x.cookie_domain); when unset (e.g. test) the cookie is host-only.
options = { key: "_move_session" }
domain = Rails.application.config.x.cookie_domain
options[:domain] = domain if domain.present?

Rails.application.config.session_store :cookie_store, **options
