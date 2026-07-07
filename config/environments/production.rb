require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Uploaded files go to Cloudflare R2 — off-box, durable object storage (#567 /
  # resolves #537). Migrated off the on-box SeaweedFS, which silently corrupted
  # ~35% of stored photos (a bad volume file since ~2026-07-01); R2 makes a
  # VM-coupled loss structurally impossible. Existing blobs were copied + repointed
  # (their per-blob service_name is already `r2`); this only points NEW uploads at
  # R2. Dev still uses :seaweedfs (config/environments/development.rb).
  config.active_storage.service = :r2

  # Browser uploads captured photos straight to R2 via a presigned PUT (#572),
  # instead of proxying 2–8 MB through the single app box. Requires R2 CORS for the
  # apex + org-subdomain origins (see new-app-recipe.md). The client falls back to
  # a server-proxied POST if a direct upload fails, so capture never breaks.
  config.x.direct_upload_enabled = true

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  # config.assume_ssl = true

  # Enforce HTTPS semantics at the app level
  config.force_ssl  = true

  # Tell Rails to treat proxied requests as HTTPS
  config.assume_ssl = true

  # Don't redirect the internal healthcheck, keep Kamal happy
  config.ssl_options = {
    redirect: {
      exclude: ->(request) { request.path == "/up" }
    }
  }

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to $stdout with the current request id as a default log tag.
  # config.log_tags = [ :request_id ]
  # config.logger   = ActiveSupport::TaggedLogging.logger($stdout)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  # config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  config.action_mailer.raise_delivery_errors = true

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "move-easy.org", protocol: "https" }
  config.action_mailer.asset_host = "https://move-easy.org"

  # Multi-tenancy: the apex move-easy.org is the marketing/login host; org
  # subdomains are <slug>.move-easy.org. Cookies are host-only (#280) — the apex
  # session does not carry to subdomains; the post-login handoff token bridges it.
  config.x.tenant_zone = "move-easy.org"

  # Action Cable (#239): the settings page lives on an org subdomain, so the live
  # indexing-progress WebSocket opens from https://<slug>.move-easy.org. Allow the
  # apex and any org subdomain (behind Cloudflare → kamal-proxy, which both pass
  # the WS upgrade); reject everything else.
  config.action_cable.allowed_request_origins = [%r{\Ahttps://([a-z0-9-]+\.)?move-easy\.org\z}]

  # TODO: Find a better way to handle Docker build time vs runtime env vars
  notif_mail_username = if ENV["SECRET_KEY_BASE_DUMMY"]
                          ENV.fetch("NOTIF_MAIL_USERNAME", nil) # For Docker build time
                        else
                          ENV.fetch("NOTIF_MAIL_USERNAME") # Enforce presence in production
                        end
  notif_mail_password = if ENV["SECRET_KEY_BASE_DUMMY"]
                          ENV.fetch("NOTIF_MAIL_PASSWORD", nil) # For Docker build time
                        else
                          ENV.fetch("NOTIF_MAIL_PASSWORD") # Enforce presence in production
                        end

  config.action_mailer.delivery_method = :smtp
  config.action_mailer.default_options = { from: ENV.fetch("NOTIF_MAIL_FROM", "move@joelazemar.com") }
  config.action_mailer.smtp_settings = {
    address: ENV.fetch("NOTIF_MAIL_HOST", "mail.smtp2go.com"),
    port: ENV.fetch("NOTIF_MAIL_PORT", "587").to_i,
    user_name: notif_mail_username,
    password: notif_mail_password,
    authentication: :plain,
    enable_starttls_auto: true
  }

  # config.x.notif_mail_to = ENV.fetch("NOTIF_MAIL_TO", "joel.azemar@gmail.com")

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [:id]

  # Host-header allowlist. kamal-proxy forwards every host to the app (no
  # `host:` filter, for the wildcard tenant model), so reject unexpected Host
  # headers here — direct-to-origin-IP requests or other domains pointed at the
  # box. The LEADING DOT matters: a dotted String permits the apex AND every
  # `<slug>.move-easy.org` tenant (ActionDispatch::HostAuthorization); without
  # it, only the bare apex would match and all tenant subdomains would 403.
  config.hosts << ".move-easy.org"
  # The health-check endpoint must answer regardless of Host (kamal-proxy's probe
  # may not carry the public host), so skip host authorization for it.
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end
