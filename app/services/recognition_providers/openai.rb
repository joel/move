# frozen_string_literal: true

module RecognitionProviders
  # Thin OpenAI vision adapter (selected with RECOGNITION_PROVIDER=openai). Uses
  # strict Structured Outputs so the model is constrained to OBJECTS_SCHEMA — no
  # fences, no prose, almost nothing left for the parser backstop to do. Not
  # exercised in CI. Returns the normalized Result and never leaks the raw
  # response upward.
  class Openai < Base
    ENDPOINT = "https://api.openai.com/v1/chat/completions"

    def identify(image:, context:)
      key = ENV["OPENAI_API_KEY"].presence or raise "OPENAI_API_KEY is not set"
      # TODO: confirm the production model string (gpt-4o-mini kept as the working
      # default; a GPT-4.1/5.x mini is cheaper/stronger once the string is pinned).
      model = ENV.fetch("OPENAI_RECOGNITION_MODEL", "gpt-4o-mini")
      json = post_json(
        ENDPOINT,
        headers: { "Authorization" => "Bearer #{key}" },
        body: body(model, image, context)
      )
      content = json.dig("choices", 0, "message", "content").to_s
      Result.new(provider: "openai", provider_model: model, objects: normalize(extract_objects(content)))
    end

    private

    def body(model, image, context)
      img = encoded_image(image)
      {
        model: model,
        messages: [{
          role: "user",
          content: [
            { type: "text", text: prompt(context) },
            { type: "image_url", image_url: {
              url: "data:#{img[:media_type]};base64,#{img[:base64]}",
              detail: "high"
            } }
          ]
        }],
        response_format: {
          type: "json_schema",
          json_schema: { name: "detected_objects", strict: true, schema: OBJECTS_SCHEMA }
        }
      }
    end
  end
end
