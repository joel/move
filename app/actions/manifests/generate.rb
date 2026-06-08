# frozen_string_literal: true

module Manifests
  # E1 — assembles the data for a Box's authenticated A4 manifest and records the
  # sensitive read. Viewing the contents is auditable (Domain §12.3), so the side
  # effect goes through a Rails.event ("manifest.viewed") → Manifests::AuditSubscriber,
  # never a model callback (see the events-not-callbacks convention used by D8).
  # Read-only: nothing is mutated.
  class Generate < BaseAction
    def call(box:, actor:)
      items = box.items.in_box.includes(:category, :tags).ordered.to_a
      yield emit_event(box, actor)
      Success(box: box, items: items)
    end

    private

    def emit_event(box, actor)
      Rails.event.notify(
        "manifest.viewed", box_id: box.id, move_id: box.move_id, actor_id: actor&.id
      )
      Success()
    end
  end
end
