# frozen_string_literal: true

module RecognitionProviders
  # Thin OpenAI vision adapter (selected with RECOGNITION_PROVIDER=openai). Not
  # exercised in CI; shaped on the identify_objects.rb prototype. Returns the
  # normalized Result and never leaks the raw response upward.
  class Openai < Base
    ENDPOINT = "https://api.openai.com/v1/chat/completions"

    def identify(image:, context:)
      key = ENV["OPENAI_API_KEY"].presence or raise "OPENAI_API_KEY is not set"
      model = ENV.fetch("OPENAI_RECOGNITION_MODEL", "gpt-4o-mini")
      json = post_json(ENDPOINT, headers: { "Authorization" => "Bearer #{key}" }, body: body(model, image, context))
      content = json.dig("choices", 0, "message", "content").to_s
      Result.new(provider: "openai", provider_model: model, objects: normalize(parse_array(content)))
    end

    private

    def body(model, image, context)
      {
        model: model,
        messages: [{
          role: "user",
          content: [
            { type: "text", text: prompt(context) },
            { type: "image_url", image_url: { url: data_url(image) } }
          ]
        }]
      }
    end
  end
end
