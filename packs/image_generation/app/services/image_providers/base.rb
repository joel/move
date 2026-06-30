# frozen_string_literal: true

# pack_public: true -- public API of packs/image_generation: the provider base + Base::MissingApiKey error (Items::GenerateImage rescues it).
# Kept in its layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module ImageProviders
  # Adapter contract + shared machinery for item-image generation. Subclasses turn
  # a text prompt into a normalized Result (raw image bytes + content type) and
  # must never leak vendor response structure upward. Mirrors
  # RecognitionProviders::Base — strict BYO, ProviderHttp transport.
  class Base
    include ProviderHttp

    # Raised when a vendor adapter is asked to run without this Move's own key.
    # Strict BYO: the adapter never reaches for a shared/ENV credential. Surfaced
    # to the user as "add your key in Settings".
    class MissingApiKey < StandardError; end

    # Built per Move with that Move's key (ImageProviders.for_move). `model` is
    # optional — each adapter falls back to its DEFAULT_MODEL.
    def initialize(api_key: nil, model: nil)
      @api_key = api_key.presence
      @model = model.presence
    end

    # @param prompt [String] a short description of the thing to depict
    # @return [ImageProviders::Result]
    def generate(prompt:)
      raise NotImplementedError, "#{self.class} must implement #generate"
    end

    protected

    # The Move's key, or a typed failure (never a shared/ENV key).
    def api_key!
      @api_key or raise MissingApiKey, "No API key set for #{self.class.name.demodulize}"
    end

    # The configured model, or the adapter's DEFAULT_MODEL when none was injected.
    def model
      @model || self.class::DEFAULT_MODEL
    end
  end
end
