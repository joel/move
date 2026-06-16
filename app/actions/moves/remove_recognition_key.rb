# frozen_string_literal: true

module Moves
  # Clears one provider's stored Recognition API key for a Move (#185). If the
  # cleared provider is the active one, the Move becomes not-ready and recognition
  # surfaces the "add your key" state until a new key is set — that is intended.
  # Idempotent: removing an already-absent key still succeeds. Emits
  # move.recognition_key_removed (provider only, never a key value). The caller
  # owns authorization (admin) and the archived read-only guard.
  class RemoveRecognitionKey < BaseAction
    include Search::Reindexing

    def call(move:, provider:, actor: nil)
      provider = provider.to_s

      yield ensure_writable(move)
      yield validate(provider)
      embedding_ready_before = move.embedding_provider_ready?
      yield with_responsible(actor) { persist(move, provider) }
      # Removing the reused openai key (#232) flips a semantic-search Move back to
      # Fake; null + re-embed so queries don't score against stale OpenAI vectors.
      reembed_move(move) if move.embedding_provider_ready? != embedding_ready_before
      yield emit_event(move, actor, provider)
      Success(move)
    end

    private

    def validate(provider)
      return Failure(:invalid_provider) unless Move::REAL_RECOGNITION_PROVIDERS.include?(provider)

      Success(provider)
    end

    def persist(move, provider)
      move.update!("#{provider}_api_key" => nil)
      Success(move)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(move, actor, provider)
      Rails.event.notify(
        "move.recognition_key_removed",
        move_id: move.id, actor_id: actor&.id, provider: provider
      )
      Success()
    end
  end
end
