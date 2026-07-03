# frozen_string_literal: true

module Moves
  # Clears one vendor's stored API key for a Move (#242 — shared "AI Capability"
  # panel; generalizes the old RemoveRecognitionKey to every key-holding provider,
  # including search-only Voyage). Idempotent: removing an already-absent key still
  # succeeds. If the cleared key belongs to the active provider of a feature, that
  # feature surfaces its "add your key" state until a new key is set.
  #
  # Removing the active *embedding* provider's key flips semantic search back to
  # Fake, so it starts a tracked re-embedding run (#239) to clear the now-stale
  # vectors. Emits move.provider_key_removed (provider only, never a key value).
  # The caller owns authorization (admin) and the archived guard.
  class RemoveProviderKey < BaseAction
    #: (move: untyped, provider: untyped, ?actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, provider:, actor: nil)
      provider = provider.to_s

      yield ensure_writable(move)
      yield validate(provider)
      embedding_ready_before = move.embedding_provider_ready?
      yield persist(move, provider)
      reembed_if_search_space_flipped(move, provider, embedding_ready_before)
      yield emit_event(move, actor, provider)
      Success(move)
    end

    private

    #: (untyped provider) -> Dry::Monads::Result[untyped, untyped]
    def validate(provider)
      return Failure(:invalid_provider) unless Move::PROVIDER_KEYS.include?(provider)

      Success()
    end

    #: (untyped move, untyped provider) -> Dry::Monads::Result[untyped, untyped]
    def persist(move, provider)
      move.update!("#{provider}_api_key" => nil)
      Success(move)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    #: (untyped move, untyped provider, untyped was_ready) -> untyped
    def reembed_if_search_space_flipped(move, provider, was_ready)
      return unless provider == move.embedding_provider
      return if move.embedding_provider_ready? == was_ready

      IndexingRuns::Start.new.call(move: move, provider: move.embedding_provider)
    end

    #: (untyped move, untyped actor, untyped provider) -> Dry::Monads::Success[nil]
    def emit_event(move, actor, provider)
      Rails.event.notify(
        "move.provider_key_removed", move_id: move.id, actor_id: actor&.id, provider: provider
      )
      Success()
    end
  end
end
