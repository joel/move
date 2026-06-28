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

    # Raised when a vendor adapter is asked to run without this Move's own key.
    # Strict BYO: the adapter never reaches for a shared/ENV credential. Surfaced
    # as RecognitionRun error_category :missing_key → "add your key in Settings".
    class MissingApiKey < StandardError
    end

    # Adapters are built per Move with that Move's key (RecognitionProviders
    # .for_move). `model` is optional — each adapter falls back to its DEFAULT_MODEL.
    def initialize(api_key: nil, model: nil)
      @api_key = api_key.presence
      @model = model.presence
    end

    # Shared envelope for the two JSON-Schema providers (OpenAI strict outputs +
    # Anthropic tool input_schema). Gemini speaks a different dialect and keeps
    # its own copy. Root is an object because OpenAI strict mode forbids a
    # top-level array, so every provider returns {"objects" => [...]}. Strict
    # mode also requires every property to be listed in `required`, so the model
    # always returns its best category guess, a fragility call, and a tag list
    # (an empty array when nothing applies).
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
            required: %w[label confidence category tags],
            properties: {
              label: { type: "string" },
              confidence: { type: "number" },
              category: { type: "string" },
              tags: { type: "array", items: { type: "string" } }
            }
          }
        }
      }
    }.freeze

    # Structured-output envelope for the contents-summary call (Boxes::SuggestDescription).
    # A plain object with one string — the OpenAI strict / Anthropic tool dialects share
    # this; Gemini keeps its own uppercase copy. Forces a clean string back, not prose.
    DESCRIPTION_SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[description],
      properties: { description: { type: "string" } }
    }.freeze

    # @param image [ActiveStorage::Attached::One] the Media image attachment
    # @param context [Hash] move vocabulary + box context (category/tag names, room)
    # @return [RecognitionProviders::Result]
    def identify(image:, context:)
      raise NotImplementedError, "#{self.class} must implement #identify"
    end

    # Summarise a box's items into one short contents description string. Text-only
    # (no image), so it reuses the same key/model/transport as #identify. `items` is
    # an Array<Hash> of { label:, category: } built by Boxes::SuggestDescription.
    # @return [String]
    def summarize_contents(items:)
      raise NotImplementedError, "#{self.class} must implement #summarize_contents"
    end

    protected

    # The Move's key, or a typed failure (never a shared/ENV key). The provider
    # label rides in the message for the error log only — it is never shown to the
    # user (error_category maps it to localized copy; error_detail returns nil for
    # non-transport messages).
    def api_key!
      @api_key or raise MissingApiKey, "No API key set for #{self.class.name.demodulize}"
    end

    # The configured model, or the adapter's DEFAULT_MODEL when none was injected.
    def model
      @model || self.class::DEFAULT_MODEL
    end

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
    # each item (category), flags fragility, and proposes tags; a blank category
    # becomes nil so materialization leaves the item uncategorised rather than
    # inventing one, and tag names are stripped, blank-dropped and deduped.
    def normalize(raw_objects)
      Array(raw_objects).filter_map do |obj|
        label = fetch(obj, :label).to_s
        next if label.blank?

        DetectedObject.new(
          label: label,
          confidence: fetch(obj, :confidence)&.to_f&.clamp(0.0, 1.0),
          category: fetch(obj, :category).to_s.strip.presence,
          tags: Array(fetch(obj, :tags)).map { it.to_s.strip }.compact_blank.uniq
        )
      end
    end

    def fetch(obj, key)
      obj[key.to_s] || obj[key]
    end

    # Vocabulary-aware prompt shared by every adapter. context carries :room plus
    # :categories and :tags (names from the move's category and item-applicable
    # tag vocabularies) built in RecognitionRuns::Process#context. `category` and
    # `tags` are distinct structured-output fields mapping to distinct models, so
    # both vocabularies are offered as candidates without conflating them.
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

      tags = Array(context[:tags]).map(&:to_s).compact_blank.uniq
      lines << if tags.any?
                 "Add a short list of descriptive tags to each item (at most a few). Prefer " \
                   "these existing tags when they fit (#{tags.join(", ")}); only introduce a new, " \
                   "concise tag when it adds real signal. Use an empty list when none apply."
               else
                 "Add a short list of concise descriptive tags to each item (at most a few, " \
                   "e.g. Heavy, Valuable, Seasonal), or an empty list when none apply."
               end

      lines << "Give one entry per distinct item and collapse identical duplicates into a " \
               "single entry. Ignore the box itself, packing materials " \
               "(paper, bubble wrap, tape) and anything in the background. Skip whatever is " \
               "too occluded or blurry to identify rather than guessing. Treat confidence as " \
               "your rough certainty from 0 to 1."
      lines.join(" ")
    end

    # Text prompt for the contents-summary call. Lists the box's items and asks for
    # one short, comma-separated description of the main things it carries — no
    # sentence, no trailing period — so the result reads like "Clothes, Electronics,
    # Books". `items` is an Array<Hash> of { label:, category: }.
    def summarize_prompt(items)
      lines = Array(items).filter_map do |entry|
        label = entry[:label].to_s.strip
        next if label.blank?

        category = entry[:category].to_s.strip
        suffix = category.present? ? " (#{category})" : ""
        "#{label}#{suffix}"
      end

      "Summarise the contents of this moving box into one short, human-readable line " \
        "naming the main things it carries — a few comma-separated groups or categories " \
        "(e.g. \"Clothes, Electronics, Books\"). Keep it under about ten words, no full " \
        "sentence and no trailing period. Items in the box: #{lines.join("; ")}."
    end

    # Pull the description string out of a structured payload — a parsed Hash
    # (Anthropic tool_use.input) or a raw JSON string (OpenAI/Gemini content). A
    # missing/blank/non-string description raises so model drift fails loudly
    # instead of becoming an empty suggestion.
    def extract_description(payload)
      data = payload.is_a?(String) ? parse_structured(payload) : payload
      value = data.is_a?(Hash) ? (data["description"] || data[:description]) : nil
      return value.strip if value.is_a?(String) && value.strip.present?

      raise ProviderHttp::Error, "#{self.class.name} returned a 2xx with no description"
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
    rescue StandardError # rubocop:disable Move/BroadRescue -- vips absent (NameError)/bad input → original bytes
      nil # vips absent (NameError) or unsupported input — use the original bytes.
    end
  end
end
