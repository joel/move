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

  # 2xx → the parsed JSON body. Anything else raises with the status and the
  # vendor's `error.message` (falling back to the bare status), never the key.
  def parse_response(res)
    parsed = parse_body(res.body)
    return parsed if res.code.to_i.between?(200, 299)

    detail = parsed.dig("error", "message").presence || "HTTP #{res.code}"
    raise Error, "#{self.class.name} request failed (#{res.code}): #{detail}"
  end

  def parse_body(raw)
    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    {}
  end
end
