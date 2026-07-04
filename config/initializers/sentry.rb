# frozen_string_literal: true

# Error monitoring — Sentry (#528).
#
# Init is gated on SENTRY_DSN presence: the DSN is provisioned in production
# via Doppler (move/prd) → Kamal env (an OPTIONAL secret, same pattern as
# GOOGLE_CLIENT_ID) and absent in development/test — where this file then does
# nothing at all: no hub, no railtie instrumentation, no /.*/ notification
# subscriber, no per-request middleware work. (Sentry.init with a nil DSN
# would still install ALL of that and just never send.) enabled_environments
# is a second, independent gate: an ambient prod DSN in a dev shell (a
# `doppler run` against move/prd, a copied .env) must not ship local errors
# to the production project. The DSN is deliberately not committed — this
# repository is public, and a published DSN invites junk events.
#
# send_default_pii ships request context (user IP, headers, bodies, query
# strings — on the event AND on http breadcrumbs), and Sentry does NOT apply
# Rails' filter_parameters to any of it. In this app that context carries live
# auth material: Rodauth magic-link `key`s (in query strings, and literalized
# into Sequel's SQL — Sequel uses no binds), session/remember cookies, MCP
# Bearer tokens, auth-mailer job arguments, outbound OAuth bodies
# (GOOGLE_CLIENT_SECRET) and the One Tap tokeninfo query (`id_token`). The
# scrubbing below therefore FAILS CLOSED: anything that cannot be positively
# filtered is dropped, and the before_send hook must mutate and RETURN THE
# EVENT OBJECT — sentry-ruby 6.x silently discards the event when the callback
# returns a hash (the older documented `filter.filter(event.to_hash)` pattern
# kills every event).
#
# spec/config/sentry_spec.rb pins all of this behaviour (it loads this file
# with a stubbed DSN, since the guard means test boots without Sentry).
sentry_dsn = ENV.fetch("SENTRY_DSN", nil)

if sentry_dsn.present?
  Sentry.init do |config|
    config.dsn = sentry_dsn
    config.enabled_environments = %w[production]
    config.breadcrumbs_logger = %i[active_support_logger http_logger]
    config.send_default_pii = true

    # Raw SQL breadcrumbs would carry Sequel-literalized Rodauth secrets; keep
    # the sql.active_record crumbs (name/cached are useful) but never the
    # statement text.
    config.rails.active_support_logger_subscription_items["sql.active_record"] -= [:sql]

    param_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    scrub_query = lambda do |query|
      Rack::Utils.build_query(param_filter.filter(Rack::Utils.parse_query(query)))
    rescue StandardError # rubocop:disable Move/BroadRescue -- fail closed: an unparseable query string (Rack raises on bad %-encoding) is dropped, never shipped raw — and a scrub failure must not lose the event itself
      "[FILTERED]"
    end

    # Form bodies arrive as a Hash, everything else (JSON — e.g. MCP JSON-RPC —
    # XML, plain text) as a raw String that ParameterFilter cannot see into:
    # filter hashes key-wise, parse JSON and filter it, drop anything else.
    scrub_body = lambda do |data|
      case data
      when Hash then param_filter.filter(data)
      when String then JSON.generate(param_filter.filter({ "_" => JSON.parse(data) }).fetch("_"))
      else data
      end
    rescue StandardError # rubocop:disable Move/BroadRescue -- fail closed: an unparseable body is dropped, never shipped raw — and a scrub failure must not lose the event itself
      "[FILTERED]"
    end

    config.before_send = lambda do |event, _hint|
      if (request = event.request)
        request.cookies = nil
        request.headers&.delete("Authorization")
        request.data = scrub_body.call(request.data)
        request.query_string = scrub_query.call(request.query_string) if request.query_string.present?

        # Defense-in-depth: Rodauth redirects the magic-link `key` out of the
        # URL before rendering anything, so today no in-app Referer carries a
        # secret — but a future URL-borne token shouldn't get a free channel.
        if (referer = request.headers&.[]("Referer")) && referer.include?("?")
          path, query = referer.split("?", 2)
          request.headers["Referer"] = "#{path}?#{scrub_query.call(query)}"
        end
      end

      # The ActiveJob integration attaches raw job arguments to event.extra.
      # They are positional — no key for ParameterFilter to match — and a
      # failed auth-mailer job would carry the live magic-link key, so drop
      # them (job class / job_id / queue remain for triage).
      event.extra&.delete(:arguments)

      # http_logger crumbs carry the outbound query string + request body when
      # send_default_pii is on (OAuth token exchange, One Tap tokeninfo);
      # strip those, filter what remains.
      # (members, not buffer: the ring buffer is nil-padded to its full size)
      event.breadcrumbs&.members&.each do |crumb|
        next unless crumb.data.is_a?(Hash)

        crumb.data = param_filter.filter(crumb.data.except(:body, "body", :query, "query"))
      end

      event
    end
  end
end
