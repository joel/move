# frozen_string_literal: true

module Moves
  # Sets a Move's active Recognition provider and (for a real provider) its model
  # override. The key itself is managed separately in the shared AI Capability
  # panel (Moves::SetProviderKey, #242), so this action no longer takes one. Strict
  # BYO still holds: a real provider can only be selected once its key is stored
  # (the UI also disables keyless options), so recognition never falls back to a
  # shared account. The model override (#187) IS shown, so a blank or
  # default-matching value clears it and the adapter falls back to DEFAULT_MODEL.
  # `fake` needs neither. Emits an event matching what changed —
  # move.recognition_provider_changed on a switch, move.recognition_model_changed
  # when only the model override changed — so the feed never reads a model edit as
  # a provider switch (#187). The caller owns authorization (admin) and the
  # archived read-only guard.
  class SetRecognitionProvider < BaseAction
    def call(move:, provider:, model: nil, actor: nil)
      provider = provider.to_s
      model = model.to_s.strip

      yield ensure_writable(move)
      yield validate(provider)
      yield ensure_key_present(move, provider)
      before = { provider: move.recognition_provider, model: move.recognition_model_for(provider) }
      yield with_responsible(actor) { persist(move, provider, model) }
      yield emit_event(move, actor, provider, before)
      Success(move)
    end

    private

    def validate(provider)
      return Failure(:invalid_provider) unless Move::RECOGNITION_PROVIDERS.include?(provider)

      Success(provider)
    end

    # Strict BYO: a real provider can only be selected once its key is stored (set
    # in the AI Capability panel). fake needs none.
    def ensure_key_present(move, provider)
      return Success() unless Move::REAL_RECOGNITION_PROVIDERS.include?(provider)
      return Success() if move.recognition_api_key_for(provider).present?

      Failure(:api_key_required)
    end

    # The model override is always written: blank or default-matching stores nil so
    # the row keeps tracking the adapter's DEFAULT_MODEL as it evolves.
    def persist(move, provider, model)
      attrs = { recognition_provider: provider }
      attrs[:"#{provider}_model"] = model_override(provider, model) if Move::REAL_RECOGNITION_PROVIDERS.include?(provider)
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
  end
end
