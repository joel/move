# frozen_string_literal: true

# Error monitoring (#528) + performance tracing/profiling (#531) — Sentry.
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

    # Performance monitoring (#531): trace every request (low-traffic app —
    # lower towards 0.2 if event volume/quota ever becomes a concern) and
    # profile every traced request (relative to traces_sample_rate; StackProf
    # must be loaded at boot or the profiler silently no-ops — the stackprof
    # gem is therefore global in the Gemfile, not dev-only).
    #
    # Accepted limitation: StackProf is process-global and non-reentrant, and
    # prod runs Solid Queue inside the Puma process (SOLID_QUEUE_IN_PUMA), so
    # when a job and a request are traced concurrently only the first gets a
    # profile (Sentry logs "running elsewhere" and drops the other). Profiles
    # are best-effort under concurrency; traces are unaffected.
    config.traces_sample_rate = 1.0
    config.profiles_sample_rate = 1.0

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

    # Shared by before_send (errors) and before_send_transaction (traces) —
    # transactions carry the SAME request context and breadcrumbs as errors.
    scrub_event = lambda do |event|
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

    config.before_send = ->(event, _hint) { scrub_event.call(event) }

    # Traced db spans use the raw SQL as their description, and Rodauth's
    # Sequel layer literalizes values into it (no binds) — a traced sign-in
    # would embed the live magic-link key. Redact every SQL string literal;
    # the query shape stays readable for perf triage. Covers the standard
    # ''-doubled form (all Sequel/AR emit today) plus dollar-quoted and E''
    # escape-string forms so future hand-written SQL gets no free channel.
    # (Spans are already plain hashes here — TransactionEvent maps them via
    # Span#to_h.)
    sql_string_literals = /
      \$(\w*)\$.*?\$\1\$          # dollar-quoted: $$...$$ or $tag$...$tag$
      | [eE]'(?:[^'\\]|''|\\.)*'  # escape-string: E'...' with backslash escapes
      | '(?:[^']|'')*'            # standard: '...' with '' doubling
    /mx

    config.before_send_transaction = lambda do |event, _hint|
      scrub_event.call(event)

      event.spans&.each do |span|
        next unless span[:op].to_s.start_with?("db.") && span[:description].is_a?(String)

        span[:description] = span[:description].gsub(sql_string_literals, "'[FILTERED]'")
      end

      event
    end
  end
end
