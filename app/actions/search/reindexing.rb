# frozen_string_literal: true

module Search
  # Shared by actions that change an item's *denormalized* search context (box
  # number/room, category/tag/room name, vocab removal) without touching the item
  # rows themselves — so Item#after_commit won't fire. They enqueue a projection
  # refresh for the affected items (Domain §7.3).
  module Reindexing
    private

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
    def reembed_move(move, run: nil)
      # Bulk-clear the denormalized projection's vectors; validations are
      # irrelevant to a search projection (same rationale as the #232 migration).
      ItemSearchDocument.where(move_id: move.id)
                        .update_all(embedding: nil, embedding_model: nil, embedded_at: nil) # rubocop:disable Rails/SkipsModelValidations
      # When a run is supplied (#239), each refill job carries its id and reports
      # progress; without one (vocab edits below) the jobs just refill quietly.
      reindex_items(move.items.ids, indexing_run: run)
    end

    # Item ids whose search_text embeds this vocabulary value.
    def affected_item_ids(record)
      case record
      when Category, Tag then record.items.ids
      when Room then Item.where(box_id: record.boxes.select(:id)).ids
      else []
      end
    end
  end
end
