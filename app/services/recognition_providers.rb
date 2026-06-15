# frozen_string_literal: true

# Provider-agnostic image recognition (Domain §6, Technical Foundation §10).
# Domain code talks to RecognitionProviders, never to a vendor API directly. The
# selected adapter returns a normalized RecognitionProviders::Result.
module RecognitionProviders
  module_function

  # Build the adapter for a Move's selected provider, configured with *that Move's*
  # own API key (#185 — strict BYO, no shared/ENV fallback). A `fake`/unknown
  # provider yields the deterministic Fake adapter, which needs no key. A real
  # provider with a blank key still builds, but #identify then raises
  # Base::MissingApiKey (surfaced to the user as "add your key in Settings").
  def for_move(move)
    resolve(move.recognition_provider, api_key: move.recognition_api_key_for(move.recognition_provider))
  end

  # Name → adapter instance. Vendor adapters carry the given key (nil is allowed
  # here; #identify enforces presence). Unknown names fall back to Fake.
  def resolve(name, api_key: nil)
    case name.to_s
    when "openai" then Openai.new(api_key:)
    when "anthropic" then Anthropic.new(api_key:)
    when "gemini" then Gemini.new(api_key:)
    else Fake.new
    end
  end
end
