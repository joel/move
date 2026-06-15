# frozen_string_literal: true

module RecognitionProviders
  # Thin Anthropic (Claude) vision adapter (RECOGNITION_PROVIDER=anthropic).
  # Forces a single tool whose input_schema is OBJECTS_SCHEMA, so the structured
  # result arrives as a native tool_use input — no prose, no fences to parse.
  # Not exercised in CI. Returns the normalized Result and never leaks the raw
  # response upward.
  class Anthropic < Base
    ENDPOINT  = "https://api.anthropic.com/v1/messages"
    VERSION   = "2023-06-01"
    TOOL_NAME = "record_objects"
    # Haiku 4.5 (dated snapshot) keeps cost near the OpenAI mini tier. The default
    # when a Move sets no override (#187 — Move#anthropic_model wins via Base#model).
    DEFAULT_MODEL = "claude-haiku-4-5-20251001"

    def identify(image:, context:)
      key = api_key!
      json = post_json(
        ENDPOINT,
        headers: { "x-api-key" => key, "anthropic-version" => VERSION },
        body: body(model, image, context)
      )
      Result.new(
        provider: "anthropic", provider_model: model,
        objects: normalize(extract_objects(tool_input(json)))
      )
    end

    private

    def body(model, image, context)
      img = encoded_image(image)
      {
        model: model,
        max_tokens: 2048, # a very full box can produce a long objects array
        tool_choice: { type: "tool", name: TOOL_NAME },
        tools: [{
          name: TOOL_NAME,
          description: "Record the distinct physical objects identified in the moving-box photo.",
          input_schema: OBJECTS_SCHEMA
        }],
        messages: [{
          role: "user",
          content: [
            { type: "text", text: prompt(context) },
            { type: "image", source: {
              type: "base64", media_type: img[:media_type], data: img[:base64]
            } }
          ]
        }]
      }
    end

    # The forced tool_use block carries an already-parsed input hash.
    def tool_input(json)
      block = Array(json["content"]).find { |b| b["type"] == "tool_use" && b["name"] == TOOL_NAME }
      block&.dig("input") or
        raise ProviderHttp::Error, "#{self.class.name} returned no #{TOOL_NAME} tool_use block"
    end
  end
end
