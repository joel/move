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

      tenant = Apartment::Tenant.current
      # Defer the enqueue to the outermost transaction's commit (#648): the
      # queue lives in a separate DB the app transaction doesn't cover, so an
      # in-txn enqueue (RecognitionRuns::Process emits item.created inside its
      # materialize transaction) could be picked up pre-commit — the worker
      # would see no item and the document would never be built — and a
      # rollback would leak the job. Deferred, a rollback discards it; with no
      # open transaction (fixture wrappers are non-joinable and don't count)
      # the block runs immediately, as before. The rescue lives INSIDE the
      # deferred block on purpose: commit callbacks run with the emitter's own
      # rescue out of scope, and an unrescued raise there would propagate into
      # the just-committed action (flipping a committed run to failed — the
      # #649 class). §1#4: a missed refresh is recoverable (the next item
      # event or a full reindex); a corrupted run outcome is not.
      ActiveRecord.after_all_transactions_commit do
        Search::RefreshDocumentJob.perform_later(item_id, tenant: tenant)
      rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 a side effect must not break its emitter
        Rails.logger.warn("[search] refresh enqueue failed for item=#{item_id}: #{e.class}: #{e.message}")
      end
    end
  end
end
