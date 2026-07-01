# frozen_string_literal: true

# Pre-warm a captured photo's display variants as an event-driven side effect of
# capture (#316), never a model callback (AGENTS §2). Filtered to media.captured
# to keep dispatch cheap; the subscriber enqueues a tenancy-aware background job
# so no view ever pays the cold libvips transform on first render.
Rails.application.config.after_initialize do
  Rails.event.subscribe(MediaVariants::PrewarmSubscriber.new) { |event| event[:name] == "media.captured" }
  Rails.logger.info("[media_variants] PrewarmSubscriber registered")
rescue NameError => e
  Rails.logger.error("[media_variants] Failed to register PrewarmSubscriber: #{e.class} #{e.message}")
  raise
end
