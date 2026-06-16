# frozen_string_literal: true

module Moves
  # Sets a Move's search-embedding provider (#232 — per-Move bring-your-own-key,
  # mirroring SetRecognitionProvider). Embeddings reuse the Move's existing
  # openai_api_key, so there is no key field here — just the fake/openai flag.
  #
  # Switching providers re-embeds every item in the Move: the stored item vectors
  # and the query vector must live in the same space (same provider + model) for
  # cosine ranking to mean anything, so the change enqueues a per-Move reindex
  # (Domain §7.3). Selecting openai without a key is allowed and degrades
  # gracefully — EmbeddingProviders.for_move hands back the Fake embedder until a
  # key exists, so search stays lexical+trigram with no error. A no-op re-save
  # (same provider) skips the reindex and the event. The caller (controller) owns
  # authorization (admin) and the archived read-only guard.
  class SetEmbeddingProvider < BaseAction
    include Search::Reindexing

    def call(move:, provider:, actor: nil)
      provider = provider.to_s

      yield ensure_writable(move)
      yield validate(provider)
      before = move.embedding_provider
      return Success(move) if before == provider

      yield persist(move, provider)
      reindex_items(move.items.ids)
      yield emit_event(move, actor, provider)
      Success(move)
    end

    private

    def validate(provider)
      return Failure(:invalid_provider) unless Move::EMBEDDING_PROVIDERS.include?(provider)

      Success(provider)
    end

    def persist(move, provider)
      move.update!(embedding_provider: provider)
      Success(move)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(move, actor, provider)
      Rails.event.notify(
        "move.embedding_provider_changed",
        move_id: move.id, actor_id: actor&.id, provider: provider
      )
      Success()
    end
  end
end
