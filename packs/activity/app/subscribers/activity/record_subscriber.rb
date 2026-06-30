# frozen_string_literal: true

class Activity
  # Records each domain event into the append-only activity log (Technical
  # Foundation §8.2) — the events-not-callbacks convention (AGENTS.md §2), like
  # Search::IndexSubscriber and Manifests::AuditSubscriber. Runs synchronously in
  # the emitting request/job, so Apartment::Tenant.current is still the tenant and
  # the write lands in the right schema. A failure here is logged and swallowed:
  # the feed must never break the domain operation that produced the event.
  class RecordSubscriber
    def emit(event)
      attrs = Builder.new(event).call
      return unless attrs

      Activity.create!(attrs)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 subscriber must not break emitter
      Rails.logger.error("[activity] #{event[:name]} dropped: #{e.class}: #{e.message}")
    end
  end
end
