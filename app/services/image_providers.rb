# frozen_string_literal: true

# Provider-agnostic item-image generation (#416, the opt-in "✨ generate image"
# for photo-less manual items). Domain code asks ImageProviders for an image; the
# selected adapter returns a normalized ImageProviders::Result. Mirrors
# RecognitionProviders / EmbeddingProviders — per-Move bring-your-own-key, no
# shared/ENV credential.
module ImageProviders
  module_function

  # Build the generator for a Move's configured image provider, using *that
  # Move's* own API key (strict BYO). A Move that hasn't configured a real
  # provider with its key falls back to the network-free Fake generator (used by
  # the demo seed + tests), so the flow is exercisable without a vendor account.
  def for_move(move)
    return Fake.new unless move&.image_generation_ready?

    resolve(move.image_provider, api_key: move.image_api_key_for(move.image_provider))
  end

  # Name → adapter instance (mirrors RecognitionProviders.resolve). A real adapter
  # built with a blank key raises Base::MissingApiKey on #generate; for_move never
  # hands one out. Unknown/fake names fall back to the keyless Fake generator.
  def resolve(name, api_key: nil, model: nil)
    case name.to_s
    when "openai" then Openai.new(api_key:, model:)
    else Fake.new
    end
  end

  # The hardcoded DEFAULT_MODEL for a real provider — nil for fake/unknown.
  def default_model(provider)
    Openai::DEFAULT_MODEL if provider.to_s == "openai"
  end
end
