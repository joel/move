# frozen_string_literal: true

module Moves
  # Sets a Move's active Recognition provider and, optionally, that provider's own
  # API key (#185 — per-Move bring-your-own-key). Strict BYO: selecting a real
  # provider (openai/anthropic/gemini) requires a key — newly submitted or already
  # stored — so recognition never falls back to a shared deployment account.
  #
  # A blank api_key leaves the stored key untouched (the UI shows a mask, not the
  # real value, so an empty field means "keep"). The model override (#187) is the
  # opposite: it IS shown, so a blank or default-matching value clears the override
  # and the adapter falls back to its DEFAULT_MODEL. `fake` needs neither. Emits an
  # event matching what changed — move.recognition_provider_changed on a provider
  # switch, move.recognition_model_changed when only the model override changed —
  # so the activity feed never reads a model edit as a provider switch (#187). The
  # key value is never logged or emitted. The caller (controller) owns
  # authorization (admin) and the archived read-only guard.
  class SetRecognitionProvider < BaseAction
    include Search::Reindexing

    def call(move:, provider:, api_key: nil, model: nil, actor: nil)
      provider = provider.to_s
      api_key = api_key.to_s.strip
      model = model.to_s.strip

      yield ensure_writable(move)
      yield validate(provider)
      yield ensure_key_present(move, provider, api_key)
      before = { provider: move.recognition_provider, model: move.recognition_model_for(provider) }
      embedding_ready_before = move.embedding_provider_ready?
      yield with_responsible(actor) { persist(move, provider, api_key, model) }
      reembed_if_embedding_space_flipped(move, embedding_ready_before)
      yield emit_event(move, actor, provider, before)
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
    # preserves the existing (masked) key. The model override, by contrast, is
    # always written: blank or default-matching stores nil so the row keeps
    # tracking the adapter's DEFAULT_MODEL as it evolves.
    def persist(move, provider, api_key, model)
      attrs = { recognition_provider: provider }
      if Move::REAL_RECOGNITION_PROVIDERS.include?(provider)
        attrs["#{provider}_api_key"] = api_key if api_key.present?
        attrs["#{provider}_model"] = model_override(provider, model)
      end
      move.update!(attrs)
      Success(move)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # The value to store: nil when blank or equal to the provider's default (so the
    # Move tracks future default changes), otherwise the submitted model.
    def model_override(provider, model)
      return nil if model.blank? || model == RecognitionProviders.default_model(provider)

      model
    end

    # Emit the event that matches what actually changed, so the activity feed
    # stays honest: a model-only edit must not read as "switched the AI provider".
    # A provider switch (or a key-only/no-op re-save) emits provider_changed;
    # otherwise a changed model override emits recognition_model_changed with the
    # provider and the effective model (the override, or the adapter default when
    # cleared).
    def emit_event(move, actor, provider, before)
      if before[:provider] != provider || !model_override_changed?(move, provider, before[:model])
        notify("move.recognition_provider_changed", move, actor, provider: provider)
      else
        notify("move.recognition_model_changed", move, actor,
               provider: provider, model: effective_model(move, provider))
      end
      Success()
    end

    def model_override_changed?(move, provider, previous_model)
      move.recognition_model_for(provider) != previous_model
    end

    def effective_model(move, provider)
      move.recognition_model_for(provider) || RecognitionProviders.default_model(provider)
    end

    def notify(name, move, actor, **payload)
      Rails.event.notify(name, move_id: move.id, actor_id: actor&.id, **payload)
    end

    # Embeddings reuse this Move's openai_api_key (#232). Setting that key here
    # can flip the Move from "fake" embeddings to real OpenAI ones while the
    # stored item vectors are still in the old (fake) space — so when readiness
    # actually changes, null and re-embed the Move (synchronously-null +
    # background refill). A key rotation (present→present) keeps the same space
    # for a fixed model, so readiness is unchanged and nothing is re-embedded.
    def reembed_if_embedding_space_flipped(move, was_ready)
      reembed_move(move) if move.embedding_provider_ready? != was_ready
    end
  end
end
