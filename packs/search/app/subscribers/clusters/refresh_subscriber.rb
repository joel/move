# frozen_string_literal: true

module Clusters
  # Rails.event subscriber that keeps item clusters fresh (#631) — the
  # convention-aligned alternative to model callbacks (AGENTS.md §2). Any event
  # that changes the clustering inputs requests a debounced recompute for the
  # Move: item lifecycle events change the working set (name/box/presence/
  # deletion axes), and the embedding-space events change which cache rows are
  # hits (the new model's vectors fill lazily on the next run — no IndexingRuns
  # coordination, clustering never reads the search vectors). Image-generation
  # events are deliberately absent: an attached image changes no clustering
  # input. Runs synchronously in the emitting request, so Apartment tenant
  # context is still live — which means a failure here would break the emitting
  # item/box action, so the dispatch is isolated (AGENTS.md §1#4).
  class RefreshSubscriber
    # family_backfilled (#627): the hidden family is part of the embedded text
    # (normalized name + modal family), so a backfill changes clustering inputs.
    ITEM_EVENTS = %w[
      item.created item.updated item.moved item.deleted
      item.removed item.restored item.undeleted item.family_backfilled
    ].freeze
    # Box-level cascades change the searchable set WITHOUT item events (Codex
    # P2 on #632): marking a box unpacked bulk-updates its items to removed via
    # update_all, and box delete/restore cascade discard/undiscard the children.
    # status_changed is subscribed for every transition rather than decoding
    # `to:` here — a spare debounced recompute on seal is cheaper than coupling
    # this subscriber to which transitions happen to cascade.
    BOX_EVENTS = %w[box.status_changed box.deleted box.restored].freeze
    MOVE_EVENTS = %w[
      move.embedding_provider_changed move.provider_key_set move.provider_key_removed
    ].freeze
    EVENTS = (ITEM_EVENTS + BOX_EVENTS + MOVE_EVENTS).freeze

    def emit(event)
      return unless EVENTS.include?(event[:name])

      move_id = event[:payload]&.dig(:move_id)
      return if move_id.blank?

      # This runs synchronously inside the emitting action (Items::CreateManual,
      # Boxes::TransitionStatus, …). RequestRefresh does real DB work (the
      # cluster_states upsert + guarded claim), so a StatementTimeout /
      # connection error during that SQL must NOT propagate up and fail the
      # user's edit — a stale cluster is recoverable (next event / the TTL),
      # a failed item add is not. Degrade to a logged warning (§1#4; mirrors
      # the sibling BroadcastSubscriber's isolated rescue).
      Clusters::RequestRefresh.new.call(move_id: move_id)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 a side effect must not break its emitter
      Rails.logger.warn("[clusters] refresh request failed for move=#{move_id}: #{e.class}: #{e.message}")
    end
  end
end
