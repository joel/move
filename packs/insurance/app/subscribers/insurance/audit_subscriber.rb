# frozen_string_literal: true

module Insurance
  # Rails.event subscriber that records each insurance export (#702). Both
  # exports reveal a Move's full contents (the dossier adds locations + photos),
  # so the generating actions emit `insurance.declaration_generated` /
  # `insurance.dossier_generated` and this writes the audit line — the
  # events-not-callbacks convention (AGENTS.md §2), mirroring
  # Manifests::AuditSubscriber. Runs synchronously in the emitting request, so
  # Apartment::Tenant.current is still the tenant.
  class AuditSubscriber
    def emit(event)
      return unless event[:name].start_with?("insurance.")

      payload = event[:payload] || {}
      kind = event[:name].delete_prefix("insurance.").delete_suffix("_generated")
      Rails.logger.info(
        "[insurance.audit] tenant=#{Apartment::Tenant.current} kind=#{kind} " \
        "move=#{payload[:move_id]} actor=#{payload[:actor_id]} items=#{payload[:item_count]}"
      )
    end
  end
end
