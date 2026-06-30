# frozen_string_literal: true

# Provider-agnostic item-image generation (#416, the opt-in "✨ generate image"
# for photo-less manual items). Domain code asks ImageProviders for an image; the
# selected adapter returns a normalized ImageProviders::Result. Mirrors
# RecognitionProviders / EmbeddingProviders — per-Move bring-your-own-key, no
# shared/ENV credential.
module ImageProviders
  module_function

  # Build the generator for a Move's configured image provider, using *that
  # Move's* own API key (strict BYO). Only an explicitly `fake` Move (or no Move)
  # gets the network-free Fake generator; a real provider is built even without a
  # key so #generate raises MissingApiKey (the action reverts the card) instead of
  # silently faking an image — preserving BYO if the key is removed after the
  # controller hid the affordance but before the job runs (#416 Codex).
  def for_move(move)
    return Fake.new if move.nil? || move.image_provider == "fake"

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
