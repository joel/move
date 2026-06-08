# frozen_string_literal: true

module Manifests
  # Rails.event subscriber that records each authenticated manifest read (E1).
  # Viewing a box's full contents is sensitive (Domain §12.3), so Manifests::Generate
  # emits `manifest.viewed` and this writes the audit line — the events-not-callbacks
  # convention (AGENTS.md §2), mirroring Search::IndexSubscriber. Runs synchronously
  # in the emitting request, so Apartment::Tenant.current is still the tenant.
  class AuditSubscriber
    def emit(event)
      return unless event[:name] == "manifest.viewed"

      payload = event[:payload] || {}
      Rails.logger.info(
        "[manifest.audit] tenant=#{Apartment::Tenant.current} " \
        "box=#{payload[:box_id]} move=#{payload[:move_id]} actor=#{payload[:actor_id]}"
      )
    end
  end
end
