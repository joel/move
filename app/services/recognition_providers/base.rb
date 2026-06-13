# frozen_string_literal: true

require "base64"
begin
  require "vips"
rescue LoadError
  # ruby-vips is optional; without it we fall back to the raw attachment bytes.
end

module RecognitionProviders
  # Adapter contract + shared machinery. Subclasses turn an image + move/box
  # context into a normalized Result and must never leak vendor response
  # structure upward. The schema, image down-scaling, vocabulary prompt and
  # object extraction all live here so each adapter is just transport + envelope.
  class Base
    include ProviderHttp

    MAX_IMAGE_EDGE = 1536

    # Shared envelope for the two JSON-Schema providers (OpenAI strict outputs +
    # Anthropic tool input_schema). Gemini speaks a different dialect and keeps
    # its own copy. Root is an object because OpenAI strict mode forbids a
    # top-level array, so every provider returns {"objects" => [...]}. Strict
    # mode also requires every property to be listed in `required`, so the model
    # always returns its best category guess and a fragility call.
    OBJECTS_SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[objects],
      properties: {
        objects: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[label confidence count category fragile],
            properties: {
              label: { type: "string" },
              confidence: { type: "number" },
              count: { type: "integer" },
              category: { type: "string" },
              fragile: { type: "boolean" }
            }
          }
        }
      }
    }.freeze

    # @param image [ActiveStorage::Attached::One] the Media image attachment
    # @param context [Hash] move vocabulary + box context (category/tag names, room)
    # @return [RecognitionProviders::Result]
    def identify(image:, context:)
      raise NotImplementedError, "#{self.class} must implement #identify"
    end

    protected

    # Pull the objects array out of a structured payload. Accepts a parsed
    # Hash/Array (e.g. Anthropic tool_use.input) or a raw JSON string
    # (OpenAI/Gemini content). A genuinely empty box yields {"objects": []} —
    # a legitimate zero-detection success. Anything that isn't an array raises,
    # so prose / model drift fails loudly and retryably instead of becoming a
    # phantom `succeeded` with zero items (transport/API failures already raise
    # upstream via ProviderHttp).
    def extract_objects(payload)
      data  = payload.is_a?(String) ? parse_structured(payload) : payload
      array = data.is_a?(Hash) ? data["objects"] : data
      return array if array.is_a?(Array)

      raise ProviderHttp::Error, "#{self.class.name} returned a 2xx with no objects array"
    end

    def parse_structured(content)
      JSON.parse(content)
    rescue JSON::ParserError
      # Structured output should already be clean JSON; if a model wraps it in
      # prose/fences anyway, recover the bracketed body as a backstop.
      snippet = content.to_s[/\{.*\}|\[.*\]/m]
      if snippet
        begin
          return JSON.parse(snippet)
        rescue JSON::ParserError
          # fall through to raise
        end
      end
      # Deliberately generic: JSON::ParserError#message embeds the offending
      # model content, and fail_run would persist it to
      # recognition_runs.error_message. Raw vendor/model content is never stored.
      raise ProviderHttp::Error, "#{self.class.name} returned a 2xx with a malformed JSON body"
    end

    # Coerce provider hashes into DetectedObjects, dropping anything without a
    # label and clamping confidence into range (the schemas pin types, not
    # numeric bounds). Accepts string or symbol keys. The model also classifies
    # each item (category) and flags fragility; a blank category becomes nil so
    # materialization leaves the item uncategorised rather than inventing one.
    def normalize(raw_objects)
      Array(raw_objects).filter_map do |obj|
        label = fetch(obj, :label).to_s
        next if label.blank?

        DetectedObject.new(
          label: label,
          confidence: fetch(obj, :confidence)&.to_f&.clamp(0.0, 1.0),
          count: (fetch(obj, :count) || 1).to_i,
          category: fetch(obj, :category).to_s.strip.presence,
          fragile: ActiveModel::Type::Boolean.new.cast(fetch(obj, :fragile)) || false
        )
      end
    end

    def fetch(obj, key)
      obj[key.to_s] || obj[key]
    end

    # Vocabulary-aware prompt shared by every adapter. context carries :room plus
    # :categories (names from the move's category vocabulary) built in
    # RecognitionRuns::Process#context. Only categories are offered as candidates —
    # the structured output has a single `category` field that maps to a Category,
    # so feeding item tags here would let the model return a tag as a category.
    def prompt(context)
      lines = ["Identify the distinct physical objects in this moving-box photo."]
      lines << "The box is in the #{context[:room]}." if context[:room].present?

      categories = Array(context[:categories]).map(&:to_s).compact_blank.uniq
      lines << if categories.any?
                 "Classify each item into a category. Prefer one of these existing " \
                   "categories when it clearly fits (#{categories.join(", ")}); only introduce a " \
                   "new, concise category when none of these match."
               else
                 "Classify each item with a concise category (e.g. Kitchenware, Books, Electronics)."
               end

      lines << "Set fragile to true for items that can break or scratch easily — glass, " \
               "ceramics, electronics, screens, artwork, mirrors, bottles — and false otherwise."
      lines << "Give one entry per distinct item and collapse identical duplicates into a " \
               "single entry with a count. Ignore the box itself, packing materials " \
               "(paper, bubble wrap, tape) and anything in the background. Skip whatever is " \
               "too occluded or blurry to identify rather than guessing. Treat confidence as " \
               "your rough certainty from 0 to 1."
      lines.join(" ")
    end

    # Down-scaled, EXIF-oriented JPEG for the vision call: { base64:, media_type: }.
    # Phone originals are 12MP+; past ~1536px the models gain nothing while we pay
    # in image tokens and latency. Falls back to the raw attachment if vips is
    # missing or the format can't be processed.
    def encoded_image(image)
      raw = image.download
      bytes, media = downscale_jpeg(raw) || [raw, image.content_type]
      { base64: Base64.strict_encode64(bytes), media_type: media }
    end

    def downscale_jpeg(raw)
      img   = Vips::Image.new_from_buffer(raw, "").autorot
      scale = MAX_IMAGE_EDGE.to_f / [img.width, img.height].max
      img   = img.resize(scale) if scale < 1.0
      [img.jpegsave_buffer(Q: 82, strip: true), "image/jpeg"]
    rescue StandardError
      nil # vips absent (NameError) or unsupported input — use the original bytes.
    end
  end
end
