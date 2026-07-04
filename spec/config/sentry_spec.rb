# frozen_string_literal: true

require "rails_helper"
require "sentry/test_helper"

# #528 — Sentry ships request context with events (send_default_pii), but the
# raw payload can carry live auth material: the Rodauth magic-link `key` in
# query strings (and literalized into Sequel's SQL), session/remember cookies,
# MCP Bearer tokens, auth-mailer job arguments, and outbound OAuth bodies on
# http breadcrumbs. The initializer scrubs all of these, failing closed.
#
# The initializer no-ops without a DSN (test boots Sentry-free), so each
# example loads it with a dummy DSN to exercise the real configuration. The
# scrub hook must also RETURN THE EVENT OBJECT — sentry-ruby 6.x silently
# discards the event when before_send returns a hash (the older documented
# pattern), so the "still delivered" assertions guard against every event
# being dropped.
RSpec.describe "Sentry request scrubbing" do # rubocop:disable RSpec/DescribeClass
  include Sentry::TestHelper

  around do |example|
    ENV["SENTRY_DSN"] = Sentry::TestHelper::DUMMY_DSN
    example.run
  ensure
    ENV.delete("SENTRY_DSN")
  end

  before do
    load Rails.root.join("config/initializers/sentry.rb")
    setup_sentry_test
  end

  after { teardown_sentry_test }

  def capture_event_for(url, opts = {})
    env = Rack::MockRequest.env_for(url, opts)
    Sentry.get_current_scope.set_rack_env(env)
    Sentry.capture_message("probe")
    sentry_events.last
  end

  it "delivers the event with its request context (before_send returns the event, not a hash)" do
    event = capture_event_for("https://demo.move-easy.org/boxes")

    expect(event).to be_a(Sentry::ErrorEvent)
    expect(event.request).to be_present
  end

  it "redacts filtered params from the query string but keeps benign ones" do
    event = capture_event_for("https://demo.move-easy.org/auth?key=magic-link-secret&foo=bar")

    expect(event.request.query_string).not_to include("magic-link-secret")
    expect(event.request.query_string).to include("foo=bar")
  end

  it "drops an unparseable query string instead of shipping it raw or losing the event" do
    # env_for refuses an invalid %-escape in the URL, so inject it directly —
    # exactly what a hostile client puts on the wire.
    event = capture_event_for("https://demo.move-easy.org/boxes", "QUERY_STRING" => "q=%ZZ")

    expect(event).to be_a(Sentry::ErrorEvent)
    expect(event.request.query_string).to eq("[FILTERED]")
  end

  it "drops cookies" do
    event = capture_event_for("https://demo.move-easy.org/boxes", "HTTP_COOKIE" => "_move_session=session-secret")

    # Assert on the request interface, not the whole event: message events
    # carry a thread stacktrace whose source-context lines include THIS spec
    # file, so the literal secret string always appears there.
    expect(event.request.cookies).to be_nil
    expect(event.request.to_h.to_s).not_to include("session-secret")
  end

  it "drops the Authorization header" do
    event = capture_event_for("https://demo.move-easy.org/mcp", "HTTP_AUTHORIZATION" => "Bearer integration-token")

    expect(event.request.headers).not_to have_key("Authorization")
    expect(event.request.to_h.to_s).not_to include("integration-token")
  end

  it "redacts filtered params from the Referer query string (defense-in-depth for URL-borne tokens)" do
    event = capture_event_for(
      "https://demo.move-easy.org/boxes",
      "HTTP_REFERER" => "https://demo.move-easy.org/email-auth?key=magic-link-secret&foo=bar"
    )

    expect(event.request.headers["Referer"]).not_to include("magic-link-secret")
    expect(event.request.headers["Referer"]).to include("foo=bar")
  end

  it "filters POST form data through the app's filter_parameters" do
    event = capture_event_for(
      "https://demo.move-easy.org/session",
      method: "POST", params: { "password" => "hunter2", "room" => "kitchen" }
    )

    expect(event.request.data).to include("password" => "[FILTERED]", "room" => "kitchen")
  end

  it "filters JSON bodies (kept as a raw string by Sentry) through filter_parameters" do
    event = capture_event_for(
      "https://demo.move-easy.org/mcp",
      method: "POST", input: '{"token":"mcp-secret","room":"kitchen"}', "CONTENT_TYPE" => "application/json"
    )

    expect(event.request.data).not_to include("mcp-secret")
    expect(event.request.data).to include("kitchen")
  end

  it "drops non-JSON raw bodies entirely" do
    event = capture_event_for(
      "https://demo.move-easy.org/upload",
      method: "POST", input: "key=raw-body-secret", "CONTENT_TYPE" => "text/plain"
    )

    expect(event.request.data).to eq("[FILTERED]")
  end

  it "drops job arguments from event extra (positional — unfilterable by key)" do
    Sentry.capture_message("probe", extra: { arguments: ["magic-link-key"], job_id: "j-1" })
    event = sentry_events.last

    expect(event.extra).not_to have_key(:arguments)
    expect(event.extra[:job_id]).to eq("j-1")
  end

  it "strips outbound bodies and query strings from http breadcrumbs" do
    Sentry.add_breadcrumb(
      Sentry::Breadcrumb.new(
        category: "net.http",
        data: { method: "POST", url: "https://oauth2.googleapis.com/token",
                body: "client_secret=oauth-secret", query: "id_token=one-tap-token" }
      )
    )
    Sentry.capture_message("probe")
    crumb = sentry_events.last.breadcrumbs.peek

    expect(crumb.data).not_to have_key(:body)
    expect(crumb.data).not_to have_key(:query)
    expect(crumb.data[:url]).to eq("https://oauth2.googleapis.com/token")
  end

  it "never captures raw SQL in breadcrumbs (Sequel literalizes Rodauth secrets into it)" do
    expect(
      Sentry.configuration.rails.active_support_logger_subscription_items["sql.active_record"]
    ).not_to include(:sql)
  end

  it "enables tracing and profiling (#531)" do
    expect(Sentry.configuration.traces_sample_rate).to eq(1.0)
    expect(Sentry.configuration.profiles_sample_rate).to eq(1.0)
    expect(defined?(StackProf)).to be_truthy # the profiler silently no-ops without it
  end

  it "redacts SQL string literals from traced db spans (Sequel literalizes Rodauth secrets)" do
    transaction = Sentry.start_transaction(name: "spec", op: "http.server")
    child = transaction.start_child(
      op: "db.sql.active_record",
      description: "INSERT INTO account_email_auth_keys (key) VALUES ('magic-link-secret')"
    )
    child.finish
    transaction.finish
    event = sentry_events.last

    expect(event).to be_a(Sentry::TransactionEvent)
    span = event.spans.find { |s| s[:op] == "db.sql.active_record" }
    expect(span[:description]).not_to include("magic-link-secret")
    expect(span[:description]).to include("INSERT INTO account_email_auth_keys")
  end

  it "redacts dollar-quoted and escape-string SQL literals too (future hand-written SQL)" do
    transaction = Sentry.start_transaction(name: "spec", op: "http.server")
    transaction.start_child(
      op: "db.sql.active_record",
      description: "SELECT 1 WHERE a = $$dollar-secret$$ AND b = $tag$tagged-secret$tag$ AND c = E'esc\\'ape-secret'"
    ).finish
    transaction.finish
    span = sentry_events.last.spans.find { |s| s[:op] == "db.sql.active_record" }

    expect(span[:description]).not_to include("dollar-secret")
    expect(span[:description]).not_to include("tagged-secret")
    expect(span[:description]).not_to include("ape-secret")
  end

  it "redacts path-embedded capability tokens from the request URL (Active Storage signed ids, scan tokens)" do
    event = capture_event_for("https://demo.move-easy.org/rails/active_storage/blobs/proxy/eyJfcmFpbHNSIGNED/photo.jpg")

    expect(event.request.url).not_to include("eyJfcmFpbHNSIGNED")
    expect(event.request.url).to include("/rails/active_storage/[FILTERED]")

    event = capture_event_for("https://demo.move-easy.org/scan/label-token-secret")
    expect(event.request.url).not_to include("label-token-secret")
  end

  it "does not trace Active Storage proxy requests at all (signed ids in the path)" do
    before_count = sentry_events.size
    transaction = Sentry.start_transaction(
      name: "/rails/active_storage/blobs/proxy/eyJSIGNED/photo.jpg", op: "http.server", source: :url
    )
    transaction&.finish

    expect(sentry_events.size).to eq(before_count)
  end

  it "redacts path-embedded tokens from a query-less Referer" do
    event = capture_event_for(
      "https://demo.move-easy.org/boxes",
      "HTTP_REFERER" => "https://demo.move-easy.org/scan/label-token-secret"
    )

    expect(event.request.headers["Referer"]).not_to include("label-token-secret")
  end

  it "scrubs the profile envelope's copied transaction name (raw path when routing never ran)" do
    transaction = Sentry.start_transaction(name: "/scan/label-token-secret", op: "http.server", source: :url)
    event = Sentry.get_current_client.event_from_transaction(transaction)
    event.profile = { transaction: { name: "/scan/label-token-secret" } }
    scrubbed = Sentry.configuration.before_send_transaction.call(event, {})

    expect(scrubbed.transaction).not_to include("label-token-secret")
    expect(scrubbed.profile.dig(:transaction, :name)).not_to include("label-token-secret")
  end

  it "redacts the outbound query string from traced http.client span data (One Tap id_token)" do
    transaction = Sentry.start_transaction(name: "spec", op: "http.server")
    span = transaction.start_child(op: "http.client", description: "GET https://oauth2.googleapis.com/tokeninfo")
    span.set_data("http.query", "id_token=one-tap-token")
    span.set_data("url", "https://oauth2.googleapis.com/tokeninfo")
    span.finish
    transaction.finish
    sent = sentry_events.last.spans.find { |s| s[:op] == "http.client" }

    expect(sent[:data]["http.query"]).not_to include("one-tap-token")
    expect(sent[:data]["url"]).to eq("https://oauth2.googleapis.com/tokeninfo")
  end

  it "scrubs the request context on transactions too" do
    env = Rack::MockRequest.env_for(
      "https://demo.move-easy.org/auth?key=magic-link-secret",
      "HTTP_COOKIE" => "_move_session=session-secret", "HTTP_AUTHORIZATION" => "Bearer integration-token"
    )
    Sentry.get_current_scope.set_rack_env(env)
    transaction = Sentry.start_transaction(name: "spec", op: "http.server")
    transaction.finish
    event = sentry_events.last

    expect(event).to be_a(Sentry::TransactionEvent)
    expect(event.request.cookies).to be_nil
    expect(event.request.headers).not_to have_key("Authorization")
    expect(event.request.query_string).not_to include("magic-link-secret")
  end
end
