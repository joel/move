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
  # context is still live; RequestRefresh returns Failure rather than raising,
  # so the emitting action can't be broken from here.
  class RefreshSubscriber
    ITEM_EVENTS = %w[
      item.created item.updated item.moved item.deleted
      item.removed item.restored item.undeleted
    ].freeze
    MOVE_EVENTS = %w[
      move.embedding_provider_changed move.provider_key_set move.provider_key_removed
    ].freeze
    EVENTS = (ITEM_EVENTS + MOVE_EVENTS).freeze

    def emit(event)
      return unless EVENTS.include?(event[:name])

      move_id = event[:payload]&.dig(:move_id)
      return if move_id.blank?

      Clusters::RequestRefresh.new.call(move_id: move_id)
    end
  end
end
