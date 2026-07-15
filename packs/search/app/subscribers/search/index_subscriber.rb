# frozen_string_literal: true

module Search
  # Rails.event subscriber that keeps the D8 search projection fresh by reacting
  # to item domain events — the convention-aligned alternative to a model
  # callback (AGENTS.md §2: side effects via actions/events, not models). Actions
  # emit `item.created|updated|moved` (and recognition emits
  # `item.family_backfilled`, #627 — the family is part of the indexed text);
  # this enqueues a tenant-restoring background refresh for the affected item.
  # Runs synchronously in the emitting request, so Apartment::Tenant.current is
  # still the tenant.
  class IndexSubscriber
    ITEM_EVENTS = %w[item.created item.updated item.moved item.family_backfilled].freeze

    def emit(event)
      return unless ITEM_EVENTS.include?(event[:name])

      item_id = event[:payload]&.dig(:item_id)
      return if item_id.blank?

      Search::RefreshDocumentJob.perform_later(item_id, tenant: Apartment::Tenant.current)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 a side effect must not break its emitter
      # The enqueue writes to the separate queue DB, so it can fail
      # independently of the emitting action's own (already-committed) work — a
      # missed refresh is recoverable (the next item event or a full reindex),
      # a failed user action is not. Mirrors the sibling RefreshSubscriber.
      Rails.logger.warn("[search] refresh enqueue failed for item=#{item_id}: #{e.class}: #{e.message}")
    end
  end
end
