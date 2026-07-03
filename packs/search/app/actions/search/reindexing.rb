# frozen_string_literal: true

# pack_public: true -- public API of packs/search: mixin included by Boxes::Update / Vocabularies actions to re-index on change.
# Kept in its layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Search
  # Shared by actions that change an item's *denormalized* search context (box
  # number/room, room name, vocab removal) without touching the item rows
  # themselves — so Item#after_commit won't fire. They enqueue a projection
  # refresh for the affected items (Domain §7.3).
  module Reindexing
    private

    #: (untyped item_ids, ?indexing_run: untyped) -> void
    def reindex_items(item_ids, indexing_run: nil)
      tenant = Apartment::Tenant.current
      Array(item_ids).uniq.each do |id|
        Search::RefreshDocumentJob.perform_later(id, tenant: tenant, indexing_run_id: indexing_run&.id)
      end
    end

    # Re-embed a whole Move after its *effective embedding space* changes — a
    # provider switch, or the reused OpenAI key being set/removed while openai is
    # selected (#232). Nulls every stored vector **synchronously first**, then
    # enqueues the per-item refill: during the pending window (and on any
    # backlogged/failed job) searches see nil embeddings and fall back to
    # lexical+trigram, instead of scoring the new query vector against stale
    # vectors from the old space. The jobs refill them in the Move's new space.

    #: (untyped move, ?run: untyped, ?item_ids: untyped) -> void
    def reembed_move(move, run: nil, item_ids: nil)
      # Bulk-clear the denormalized projection's vectors; validations are
      # irrelevant to a search projection (same rationale as the #232 migration).
      ItemSearchDocument.where(move_id: move.id)
                        .update_all(embedding: nil, embedding_model: nil, embedded_at: nil) # rubocop:disable Rails/SkipsModelValidations
      # When a run is supplied (#239), each refill job carries its id and reports
      # progress; the caller passes the same id snapshot it used for total_count so
      # the two can't disagree. Without a run (vocab edits) the jobs refill quietly.
      reindex_items(item_ids || move.items.ids, indexing_run: run)
    end

    # Item ids whose search_text embeds this vocabulary value (rooms only — a
    # room rename changes the box/room context denormalized into search_text).

    #: (untyped record) -> Array[untyped]
    def affected_item_ids(record)
      case record
      when Room then Item.where(box_id: record.boxes.select(:id)).ids
      else []
      end
    end
  end
end
