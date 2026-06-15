# frozen_string_literal: true

module Moves
  # Sets a Move's active Recognition provider and, optionally, that provider's own
  # API key (#185 — per-Move bring-your-own-key). Strict BYO: selecting a real
  # provider (openai/anthropic/gemini) requires a key — newly submitted or already
  # stored — so recognition never falls back to a shared deployment account.
  #
  # A blank api_key leaves the stored key untouched (the UI shows a mask, not the
  # real value, so an empty field means "keep"). `fake` needs no key. Emits
  # move.recognition_provider_changed for the audit trail — the key value is never
  # logged or emitted. The caller (controller) owns authorization (admin) and the
  # archived read-only guard.
  class SetRecognitionProvider < BaseAction
    def call(move:, provider:, api_key: nil, actor: nil)
      provider = provider.to_s
      api_key = api_key.to_s.strip

      yield ensure_writable(move)
      yield validate(provider)
      yield ensure_key_present(move, provider, api_key)
      yield with_responsible(actor) { persist(move, provider, api_key) }
      yield emit_event(move, actor, provider)
      Success(move)
    end

    private

    def validate(provider)
      return Failure(:invalid_provider) unless Move::RECOGNITION_PROVIDERS.include?(provider)

      Success(provider)
    end

    # Real provider must end up with a key: the one just submitted, or one already
    # stored for that provider. fake needs none.
    def ensure_key_present(move, provider, api_key)
      return Success() unless Move::REAL_RECOGNITION_PROVIDERS.include?(provider)
      return Success() if api_key.present? || move.recognition_api_key_for(provider).present?

      Failure(:api_key_required)
    end

    # Only overwrite the key column when a new value was submitted; a blank field
    # preserves the existing (masked) key.
    def persist(move, provider, api_key)
      attrs = { recognition_provider: provider }
      attrs["#{provider}_api_key"] = api_key if Move::REAL_RECOGNITION_PROVIDERS.include?(provider) && api_key.present?
      move.update!(attrs)
      Success(move)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(move, actor, provider)
      Rails.event.notify(
        "move.recognition_provider_changed",
        move_id: move.id, actor_id: actor&.id, provider: provider
      )
      Success()
    end
  end
end
