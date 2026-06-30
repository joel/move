# frozen_string_literal: true

module MediaVariants
  # Pre-warms a freshly captured photo's display variants in the background so the
  # gallery grid and viewers are always warm by the time anyone browses (#316) —
  # an event-driven side effect of capture, never a model callback (AGENTS §2).
  # Listens for media.captured (Captures::Create) and enqueues the tenancy-aware
  # job with the current tenant, since jobs don't inherit Apartment's tenant.
  class PrewarmSubscriber
    def emit(event)
      media_id = event[:payload]&.dig(:media_id)
      return if media_id.blank?

      MediaVariants::PrewarmJob.perform_later(media_id, tenant: Apartment::Tenant.current)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 subscriber must not break the emitting capture
      # This runs synchronously inside Captures::Create#emit_event; an enqueue
      # failure (queue down, serialization) must not fail the capture. Worst case:
      # the variant is generated lazily on first view, as it was before #316.
      Rails.logger.warn("[media_variants:prewarm] enqueue failed for media #{media_id}: #{e.class} (#{e.message})")
    end
  end
end
