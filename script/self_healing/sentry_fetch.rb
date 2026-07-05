# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module SelfHealing
  # Whitelist reducer between Sentry and every public sink of the self-healing
  # pipeline (GitHub issues, PRs, Actions logs, the agent prompt). This is an
  # ENFORCEMENT boundary, not a convention: Sentry event data is attacker-
  # influenceable (crafted request -> exception message -> would-be prompt
  # injection / PII channel), and this repo is public, so nothing leaves this
  # class unless it is on the whitelist below — exception *messages*,
  # breadcrumbs, request data, user context, and tag values never do.
  # Whitelisted identifier-shaped fields (exception class, culprit,
  # transaction, frame paths) are additionally charset-checked and truncated.
  #
  # spec/script/self_healing/sentry_fetch_spec.rb pins the boundary with
  # hostile fixture payloads.
  class SentryFetch
    API_BASE = "https://sentry.io/api/0"
    # Ruby constants, method owners (Foo::Bar#baz), file paths, route-ish
    # transactions. Anything else — spaces, quotes, braces, newlines — is not
    # an identifier and gets dropped.
    SAFE_IDENTIFIER = %r{\A[\w:#./-]+\z}
    MAX_IDENTIFIER_LENGTH = 200
    MAX_FRAMES = 20
    MIN_EVENTS_24H = 3
    MIN_USERS = 2

    #: (org: String, project: String?, token: String) -> void
    def initialize(org:, token:, project: nil)
      @org = org
      @project = project
      @token = token
    end

    # Candidate issues for triage: unresolved production errors over the
    # activity thresholds, reduced to whitelisted fields.
    #: (?query: String) -> Array[Hash[Symbol, untyped]]
    def candidate_issues(query: "is:unresolved level:error")
      issues = get("/projects/#{@org}/#{@project}/issues/", query: query, statsPeriod: "24h")
      issues.select { |issue| self.class.candidate?(issue) }
            .map { |issue| self.class.reduce_issue(issue) }
    end

    # One issue's current state (post-deploy verification reads last_seen).
    #: (String issue_id) -> Hash[Symbol, untyped]
    def issue(issue_id)
      self.class.reduce_issue(get("/organizations/#{@org}/issues/#{issue_id}/"))
    end

    #: (String issue_id) -> Hash[Symbol, untyped]
    def latest_event(issue_id)
      event = get("/organizations/#{@org}/issues/#{issue_id}/events/latest/")
      self.class.reduce_event(event)
    end

    #: (String issue_id, String status) -> void
    def update_status(issue_id, status)
      request = Net::HTTP::Put.new(URI("#{API_BASE}/organizations/#{@org}/issues/#{issue_id}/"))
      request.body = JSON.generate(status: status)
      request["Content-Type"] = "application/json"
      perform(request)
    end

    # An issue is worth an automated fix attempt when it is actively hurting:
    # >= MIN_EVENTS_24H events in the last 24h or >= MIN_USERS distinct users,
    # or Sentry marked it regressed (it came back after a release that should
    # have fixed it).
    #: (Hash[String, untyped] issue) -> bool
    def self.candidate?(issue)
      events_24h = (issue.dig("stats", "24h") || []).sum { |_timestamp, count| count.to_i }
      events_24h >= MIN_EVENTS_24H ||
        issue["userCount"].to_i >= MIN_USERS ||
        issue["substatus"] == "regressed"
    end

    #: (Hash[String, untyped] issue) -> Hash[Symbol, untyped]
    def self.reduce_issue(issue)
      {
        issue_id: issue["id"].to_s,
        short_id: sanitize_identifier(issue["shortId"]),
        exception_type: sanitize_identifier(issue.dig("metadata", "type")),
        culprit: sanitize_identifier(issue["culprit"]),
        level: sanitize_identifier(issue["level"]),
        substatus: sanitize_identifier(issue["substatus"]),
        count: issue["count"].to_i,
        user_count: issue["userCount"].to_i,
        events_24h: (issue.dig("stats", "24h") || []).sum { |_timestamp, count| count.to_i },
        first_seen: sanitize_identifier(issue["firstSeen"]),
        last_seen: sanitize_identifier(issue["lastSeen"]),
        permalink: sanitize_permalink(issue["permalink"])
      }
    end

    #: (Hash[String, untyped] event) -> Hash[Symbol, untyped]
    def self.reduce_event(event)
      {
        event_id: sanitize_identifier(event["eventID"]),
        release: sanitize_identifier(event.dig("release", "version") || tag_value(event, "release")),
        environment: sanitize_identifier(tag_value(event, "environment")),
        transaction: sanitize_identifier(tag_value(event, "transaction")&.split("?")&.first),
        exception_types: exception_values(event).map { |value| sanitize_identifier(value["type"]) },
        frames: reduced_frames(event)
      }
    end

    # In-app frames only (app code locations, not attacker input), innermost
    # MAX_FRAMES, each reduced to filename/function/line.
    #: (Hash[String, untyped] event) -> Array[Hash[Symbol, untyped]]
    def self.reduced_frames(event)
      frames = exception_values(event).flat_map { |value| value.dig("stacktrace", "frames") || [] }
      frames.select { |frame| frame["inApp"] || frame["in_app"] }
            .last(MAX_FRAMES)
            .map do |frame|
              {
                filename: sanitize_identifier(frame["filename"]),
                function: sanitize_identifier(frame["function"]),
                line: (frame["lineNo"] || frame["lineno"]).to_i
              }
            end
    end

    #: (untyped value) -> String?
    def self.sanitize_identifier(value)
      return nil unless value.is_a?(String) && !value.empty?

      value.match?(SAFE_IDENTIFIER) ? value[0, MAX_IDENTIFIER_LENGTH] : "[UNSAFE]"
    end

    # Only a Sentry-hosted https link survives; anything else (javascript:,
    # attacker-shaped strings, http downgrade) is dropped.
    #: (untyped value) -> String?
    def self.sanitize_permalink(value)
      return nil unless value.is_a?(String)

      uri = URI.parse(value)
      uri.is_a?(URI::HTTPS) && (uri.host == "sentry.io" || uri.host&.end_with?(".sentry.io")) ? value : nil
    rescue URI::InvalidURIError
      nil
    end

    #: (Hash[String, untyped] event) -> Array[Hash[String, untyped]]
    def self.exception_values(event)
      entry = (event["entries"] || []).find { |candidate| candidate["type"] == "exception" }
      entry&.dig("data", "values") || []
    end

    #: (Hash[String, untyped] event, String key) -> String?
    def self.tag_value(event, key)
      (event["tags"] || []).find { |tag| tag["key"] == key }&.fetch("value", nil)
    end

    private

    #: (String path, **untyped params) -> untyped
    def get(path, **params)
      uri = URI("#{API_BASE}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?
      perform(Net::HTTP::Get.new(uri))
    end

    #: (Net::HTTPGenericRequest request) -> untyped
    def perform(request)
      request["Authorization"] = "Bearer #{@token}"
      uri = request.uri
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      raise "Sentry API #{request.method} #{uri.path} failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "optparse"

  options = { query: "is:unresolved level:error" }
  parser = OptionParser.new do |opts|
    opts.banner = "usage: sentry_fetch.rb {list|issue|event|update-status} [options]"
    opts.on("--org ORG") { |value| options[:org] = value }
    opts.on("--project PROJECT") { |value| options[:project] = value }
    opts.on("--issue-id ID") { |value| options[:issue_id] = value }
    opts.on("--query QUERY") { |value| options[:query] = value }
    opts.on("--status STATUS") { |value| options[:status] = value }
  end
  mode = ARGV.first
  parser.parse!(ARGV[1..] || [])

  token = ENV.fetch("SENTRY_AUTOFIX_TOKEN") { abort "SENTRY_AUTOFIX_TOKEN is not set" }
  client = SelfHealing::SentryFetch.new(org: options.fetch(:org), project: options[:project], token: token)

  case mode
  when "list"
    puts JSON.pretty_generate(client.candidate_issues(query: options.fetch(:query)))
  when "issue"
    puts JSON.pretty_generate(client.issue(options.fetch(:issue_id)))
  when "event"
    puts JSON.pretty_generate(client.latest_event(options.fetch(:issue_id)))
  when "update-status"
    client.update_status(options.fetch(:issue_id), options.fetch(:status))
    puts JSON.generate(ok: true)
  else
    abort parser.banner
  end
end
