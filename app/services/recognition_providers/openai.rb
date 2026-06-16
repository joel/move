# frozen_string_literal: true

module RecognitionProviders
  # Thin OpenAI vision adapter (selected with RECOGNITION_PROVIDER=openai). Uses
  # strict Structured Outputs so the model is constrained to OBJECTS_SCHEMA — no
  # fences, no prose, almost nothing left for the parser backstop to do. Not
  # exercised in CI. Returns the normalized Result and never leaks the raw
  # response upward.
  class Openai < Base
    ENDPOINT = "https://api.openai.com/v1/chat/completions"
    # GPT-5 mini: flagship-family vision + strict structured outputs at mini-tier
    # cost. (gpt-4o-mini was prev-gen.) The default when a Move sets no override
    # (#187 — Move#openai_model wins over this via Base#model).
    DEFAULT_MODEL = "gpt-5-mini"

    def identify(image:, context:)
      key = api_key!
      json = post_json(
        ENDPOINT,
        headers: { "Authorization" => "Bearer #{key}" },
        body: body(model, image, context)
      )
      content = json.dig("choices", 0, "message", "content").to_s
      Result.new(provider: "openai", provider_model: model, objects: normalize(extract_objects(content)))
    end

    # Text-only contents summary via strict Structured Outputs (DESCRIPTION_SCHEMA).
    def summarize_contents(items:)
      key = api_key!
      json = post_json(
        ENDPOINT,
        headers: { "Authorization" => "Bearer #{key}" },
        body: {
          model: model,
          messages: [{ role: "user", content: summarize_prompt(items) }],
          response_format: {
            type: "json_schema",
            json_schema: { name: "box_description", strict: true, schema: DESCRIPTION_SCHEMA }
          }
        }
      )
      extract_description(json.dig("choices", 0, "message", "content").to_s)
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
