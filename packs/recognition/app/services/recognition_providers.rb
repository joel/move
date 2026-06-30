# frozen_string_literal: true

# pack_public: true -- public API of packs/recognition: the per-Move provider registry (.for_move / .default_model — boxes, moves, settings panel).
# Kept in its layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

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
    provider = move.recognition_provider
    resolve(provider,
            api_key: move.recognition_api_key_for(provider),
            model: move.recognition_model_for(provider))
  end

  # Name → adapter instance. Vendor adapters carry the given key (nil is allowed
  # here; #identify enforces presence) and an optional model override (nil falls
  # back to the adapter's DEFAULT_MODEL). Unknown names fall back to Fake.
  def resolve(name, api_key: nil, model: nil)
    case name.to_s
    when "openai" then Openai.new(api_key:, model:)
    when "anthropic" then Anthropic.new(api_key:, model:)
    when "gemini" then Gemini.new(api_key:, model:)
    else Fake.new
    end
  end

  # The hardcoded DEFAULT_MODEL for a real provider (#187) — the value the UI
  # shows as the default and persists nil against. Returns nil for fake/unknown.
  def default_model(provider)
    case provider.to_s
    when "openai" then Openai::DEFAULT_MODEL
    when "anthropic" then Anthropic::DEFAULT_MODEL
    when "gemini" then Gemini::DEFAULT_MODEL
    end
  end
end
