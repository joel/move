# frozen_string_literal: true

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
      json = post_json(
        ENDPOINT,
        headers: { "x-api-key" => key, "anthropic-version" => VERSION },
        body: body(model, image, context)
      )
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
  end
end
