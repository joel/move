# frozen_string_literal: true

module RecognitionProviders
  # Thin Google Gemini vision adapter (selected with RECOGNITION_PROVIDER=gemini).
  # Uses responseSchema for structured JSON. Gemini's schema dialect uses
  # uppercase type enums, so it can't share OBJECTS_SCHEMA — same envelope,
  # different spelling. The key rides in a header to keep it out of URLs and
  # logs. Not exercised in CI. Returns the normalized Result and never leaks the
  # raw response upward.
  class Gemini < Base
    HOST = "https://generativelanguage.googleapis.com/v1beta"
    # TODO: confirm the production Flash string before pinning (placeholder; newer
    # Flash models are usually the better default). The default when a Move sets no
    # override (#187 — Move#gemini_model wins via Base#model).
    DEFAULT_MODEL = "gemini-2.5-flash"

    GEMINI_SCHEMA = {
      type: "OBJECT",
      required: %w[objects],
      properties: {
        objects: {
          type: "ARRAY",
          items: {
            type: "OBJECT",
            required: %w[label confidence],
            properties: {
              label: { type: "STRING" },
              confidence: { type: "NUMBER" }
            },
            propertyOrdering: %w[label confidence]
          }
        }
      }
    }.freeze

    # Gemini's uppercase-dialect copy of DESCRIPTION_SCHEMA.
    GEMINI_DESCRIPTION_SCHEMA = {
      type: "OBJECT",
      required: %w[description],
      properties: { description: { type: "STRING" } }
    }.freeze

    def identify(image:, context:)
      key = api_key!
      json = post_json(
        "#{HOST}/models/#{model}:generateContent",
        headers: { "x-goog-api-key" => key },
        body: body(image, context)
      )
      content = json.dig("candidates", 0, "content", "parts", 0, "text").to_s
      Result.new(provider: "gemini", provider_model: model, objects: normalize(extract_objects(content)))
    end

    # Text-only contents summary via responseSchema (GEMINI_DESCRIPTION_SCHEMA).
    def summarize_contents(items:)
      key = api_key!
      json = post_json(
        "#{HOST}/models/#{model}:generateContent",
        headers: { "x-goog-api-key" => key },
        body: {
          contents: [{ role: "user", parts: [{ text: summarize_prompt(items) }] }],
          generationConfig: {
            responseMimeType: "application/json", responseSchema: GEMINI_DESCRIPTION_SCHEMA
          }
        }
      )
      extract_description(json.dig("candidates", 0, "content", "parts", 0, "text").to_s)
    end

    private

    # Field names use the canonical proto json_name (camelCase) throughout. The
    # generativelanguage API is proto3, whose JSON mapping accepts both camelCase
    # and the snake_case field name (inlineData/inline_data, mimeType/mime_type),
    # so don't "correct" these to snake_case — keep one consistent style.
    def body(image, context)
      img = encoded_image(image)
      {
        contents: [{
          role: "user",
          parts: [
            { text: prompt(context) },
            { inlineData: { mimeType: img[:media_type], data: img[:base64] } }
          ]
        }],
        generationConfig: {
          responseMimeType: "application/json",
          responseSchema: GEMINI_SCHEMA
        }
      }
    end
  end
end
