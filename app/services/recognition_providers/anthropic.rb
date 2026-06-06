# frozen_string_literal: true

require "net/http"
require "json"
require "base64"

module RecognitionProviders
  # Thin Anthropic (Claude) vision adapter (RECOGNITION_PROVIDER=anthropic). Not
  # exercised in CI; shaped on the identify_objects.rb prototype. Returns the
  # normalized Result and never leaks the raw response upward.
  class Anthropic < Base
    ENDPOINT = "https://api.anthropic.com/v1/messages"
    VERSION = "2023-06-01"

    def identify(image:, context:)
      key = ENV["ANTHROPIC_API_KEY"].presence or raise "ANTHROPIC_API_KEY is not set"
      model = ENV.fetch("ANTHROPIC_RECOGNITION_MODEL", "claude-3-5-sonnet-latest")
      json = post(key, body(model, image, context))
      content = json.dig("content", 0, "text").to_s
      Result.new(provider: "anthropic", provider_model: model, objects: normalize(parse_array(content)))
    end

    private

    def body(model, image, context)
      {
        model: model,
        max_tokens: 1024,
        messages: [{
          role: "user",
          content: [
            { type: "text", text: prompt(context) },
            { type: "image", source: {
              type: "base64", media_type: image.content_type,
              data: Base64.strict_encode64(image.download)
            } }
          ]
        }]
      }
    end

    def post(key, body)
      uri = URI(ENDPOINT)
      req = Net::HTTP::Post.new(uri)
      req["x-api-key"] = key
      req["anthropic-version"] = VERSION
      req["Content-Type"] = "application/json"
      req.body = body.to_json
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
        http.request(req)
      end
      JSON.parse(res.body)
    end

    def parse_array(content)
      JSON.parse(content[/\[.*\]/m] || content)
    rescue JSON::ParserError
      []
    end
  end
end
