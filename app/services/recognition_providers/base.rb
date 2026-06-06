# frozen_string_literal: true

module RecognitionProviders
  # Adapter contract. Subclasses turn an image + move/box context into a
  # normalized Result; they must never leak vendor response structure upward.
  class Base
    # @param image [ActiveStorage::Attached::One] the Media image attachment
    # @param context [Hash] move vocabulary + box context (category/tag names, room)
    # @return [RecognitionProviders::Result]
    def identify(image:, context:)
      raise NotImplementedError, "#{self.class} must implement #identify"
    end

    protected

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
