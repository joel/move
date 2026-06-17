# frozen_string_literal: true

# Wire live capture-panel updates to recognition domain events (#241). The
# subscriber broadcasts the re-rendered SessionPanel over ActionCable as each
# RecognitionRun advances — an event-driven side effect (AGENTS.md §2), filtered
# to recognition_run.* to keep dispatch cheap. Replaces the old polling controller.
Rails.application.config.after_initialize do
  Rails.event.subscribe(Captures::SessionBroadcastSubscriber.new) do |event|
    event[:name].start_with?("recognition_run.")
  end
end
