# frozen_string_literal: true

require "net/http"
require "json"

# Shared JSON-over-HTTPS POST for the vendor AI adapters (recognition +
# embeddings). Centralizes the one thing every adapter previously got wrong:
# checking the HTTP status. A non-2xx response raises ProviderHttp::Error
# carrying the status + the vendor's error message (status + message only —
# never the API key or the raw body), so a rate-limited / unauthorized call
# fails loudly instead of being parsed as an empty "success" (which marked a
# recognition run `succeeded` with zero objects — indistinguishable from an
# empty box).
module ProviderHttp
  class Error < StandardError; end

  private

  def post_json(endpoint, headers:, body:, open_timeout: 10, read_timeout: 60)
    uri = URI(endpoint)
    req = Net::HTTP::Post.new(uri)
    headers.each { |name, value| req[name] = value }
    req["Content-Type"] = "application/json"
    req.body = body.to_json
    res = Net::HTTP.start(
      uri.host, uri.port, use_ssl: true, open_timeout: open_timeout, read_timeout: read_timeout
    ) { |http| http.request(req) }
    parse_response(res)
  end

  # 2xx → the strictly-parsed JSON body. A 2xx with a non-JSON body (e.g. an
  # HTML proxy/interstitial page served with the wrong status) is a failure, not
  # an empty success — raise so the run fails loudly instead of normalizing
  # nothing to zero objects. Non-2xx raises with the status + the vendor's
  # `error.message` (falling back to the bare status), never the key.
  def parse_response(res)
    return parse_json!(res.body) if res.code.to_i.between?(200, 299)

    detail = parse_body(res.body).dig("error", "message").presence || "HTTP #{res.code}"
    raise Error, "#{self.class.name} request failed (#{res.code}): #{detail}"
  end

  # Strict parse for a successful response — invalid JSON is an error.
  def parse_json!(raw)
    JSON.parse(raw.to_s)
  rescue JSON::ParserError => e
    raise Error, "#{self.class.name} returned a 2xx with a non-JSON body: #{e.message}"
  end

  # Lenient parse, used only to dig an error message out of a non-2xx body.
  # Always returns a Hash: a body that is missing, non-JSON, or valid JSON that
  # isn't an object (a bare array/string/number) collapses to {} so the caller's
  # `.dig("error", "message")` stays safe and the bare-status message is used.
  def parse_body(raw)
    parsed = JSON.parse(raw.to_s)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end
end
