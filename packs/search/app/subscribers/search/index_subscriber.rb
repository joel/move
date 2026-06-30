# frozen_string_literal: true

module Search
  # Rails.event subscriber that keeps the D8 search projection fresh by reacting
  # to item domain events — the convention-aligned alternative to a model
  # callback (AGENTS.md §2: side effects via actions/events, not models). Actions
  # emit `item.created|updated|moved`; this enqueues a tenant-restoring background
  # refresh for the affected item. Runs synchronously in the emitting request, so
  # Apartment::Tenant.current is still the tenant.
  class IndexSubscriber
    ITEM_EVENTS = %w[item.created item.updated item.moved].freeze

    def emit(event)
      return unless ITEM_EVENTS.include?(event[:name])

      item_id = event[:payload]&.dig(:item_id)
      return if item_id.blank?

      Search::RefreshDocumentJob.perform_later(item_id, tenant: Apartment::Tenant.current)
    end
  end
end
