# frozen_string_literal: true

require "base64"

module RecognitionProviders
  # Adapter contract. Subclasses turn an image + move/box context into a
  # normalized Result; they must never leak vendor response structure upward.
  class Base
    include ProviderHttp

    # @param image [ActiveStorage::Attached::One] the Media image attachment
    # @param context [Hash] move vocabulary + box context (category/tag names, room)
    # @return [RecognitionProviders::Result]
    def identify(image:, context:)
      raise NotImplementedError, "#{self.class} must implement #identify"
    end

    protected

    # The vision models reply with a JSON array, sometimes fenced in ```json or
    # wrapped in prose — extract the bracketed array and parse it. A genuinely
    # empty box yields a parseable empty array `[]` (the prompt asks for ONLY a
    # JSON array), which stays a legitimate zero-detection success. But content
    # that is non-blank yet contains no parseable JSON array (prose, an apology,
    # prompt/model drift) must NOT be read as an empty box — raise so the run
    # fails loudly and is retryable, instead of a phantom `succeeded` with zero
    # items (transport/API failures already raise upstream via ProviderHttp).
    def parse_array(content)
      json = content.to_s[/\[.*\]/m]
      parsed = JSON.parse(json) if json
      raise ProviderHttp::Error, "#{self.class.name} returned a 2xx with no parseable JSON array" unless parsed.is_a?(Array)

      parsed
    rescue JSON::ParserError
      # Deliberately generic — JSON::ParserError#message embeds the offending
      # input (model content / detected labels), which fail_run would persist to
      # recognition_runs.error_message. Raw vendor/model content is never stored.
      raise ProviderHttp::Error, "#{self.class.name} returned a 2xx with a malformed JSON array"
    end

    # Coerce an array of provider hashes into DetectedObjects, dropping anything
    # without a label. Accepts string or symbol keys.
    def normalize(raw_objects)
      Array(raw_objects).filter_map do |obj|
        label = fetch(obj, :label).to_s
        next if label.blank?

        DetectedObject.new(
          label: label,
          confidence: fetch(obj, :confidence)&.to_f,
          count: (fetch(obj, :count) || 1).to_i
        )
      end
    end

    def fetch(obj, key)
      obj[key.to_s] || obj[key]
    end

    # Prompt shared by the vision adapters; mirrors the identify_objects.rb shape.
    def prompt(context)
      rooms = context[:room].present? ? " The box is in the #{context[:room]}." : ""
      "Identify the distinct physical objects in this moving-box photo.#{rooms} " \
        "Reply with ONLY a JSON array of objects, each " \
        '{"label": string, "confidence": number 0-1, "count": integer}. No prose.'
    end

    def data_url(image)
      "data:#{image.content_type};base64,#{Base64.strict_encode64(image.download)}"
    end
  end
end
