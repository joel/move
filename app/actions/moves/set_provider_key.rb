# frozen_string_literal: true

module Moves
  # Stores one vendor's API key for a Move, decoupled from which feature uses it
  # (#242 — the shared "AI Capability" panel). A key entered here powers whichever
  # features list that provider (Recognition and/or Semantic Search). Strict BYO:
  # the key is encrypted at rest and never logged or emitted.
  #
  # Setting the key for the Move's *active embedding provider* can flip semantic
  # search from Fake to real (or back), so when readiness actually changes it
  # starts a tracked re-embedding run (#239) — the stored item vectors and the
  # query vector must live in the same space. A key for a provider that isn't the
  # active search provider (or a recognition-only vendor like Anthropic) changes no
  # vectors. The caller owns authorization (admin) and the archived guard.
  class SetProviderKey < BaseAction
    #: (move: untyped, provider: untyped, api_key: untyped, ?actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(move:, provider:, api_key:, actor: nil)
      provider = provider.to_s
      api_key = api_key.to_s.strip

      yield ensure_writable(move)
      yield validate(provider, api_key)
      embedding_ready_before = move.embedding_provider_ready?
      yield persist(move, provider, api_key)
      reembed_if_search_space_flipped(move, provider, embedding_ready_before)
      yield emit_event(move, actor, provider)
      Success(move)
    end

    private

    #: (untyped provider, untyped api_key) -> Dry::Monads::Result[untyped, untyped]
    def validate(provider, api_key)
      return Failure(:invalid_provider) unless Move::PROVIDER_KEYS.include?(provider)
      return Failure(:api_key_required) if api_key.blank?

      Success()
    end

    #: (untyped move, untyped provider, untyped api_key) -> Dry::Monads::Result[untyped, untyped]
    def persist(move, provider, api_key)
      move.update!("#{provider}_api_key" => api_key)
      Success(move)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # Only the active embedding provider's key moves the search vector space; a key
    # for any other vendor leaves stored embeddings untouched.

    #: (untyped move, untyped provider, untyped was_ready) -> untyped
    def reembed_if_search_space_flipped(move, provider, was_ready)
      return unless provider == move.embedding_provider
      return if move.embedding_provider_ready? == was_ready

      IndexingRuns::Start.new.call(move: move, provider: move.embedding_provider)
    end

    #: (untyped move, untyped actor, untyped provider) -> Dry::Monads::Success[nil]
    def emit_event(move, actor, provider)
      Rails.event.notify(
        "move.provider_key_set", move_id: move.id, actor_id: actor&.id, provider: provider
      )
      Success()
    end
  end
end
