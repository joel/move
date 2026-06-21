# frozen_string_literal: true

module LabelPrintRuns
  # Pushes the live label-print status component to every subscriber of a run's
  # progress stream (#303), so the bar advances and the "Download" appears without
  # a reload. Mirrors IndexingRuns::Broadcasting (#239). `module_function` so it is
  # callable both standalone (LabelPrintRuns::Broadcasting.broadcast_status(run),
  # from the generation job) and when mixed into an action.
  module Broadcasting
    module_function

    # A broadcast must never break its emitter (AGENTS.md §1 #4): this runs
    # synchronously inside RecordProgress and inside GenerateJob. A render/backend
    # failure here must not fail the job or the action — the worst case is a missed
    # live update; the next progress event (or the run show page on load) re-renders
    # the correct state. Mirrors Captures::SessionBroadcastSubscriber#broadcast (#241).
    def broadcast_status(run)
      Turbo::StreamsChannel.broadcast_replace_to(
        run, :progress,
        target: Components::Ui::LabelPrintStatus::ID,
        html: ApplicationController.render(Components::Ui::LabelPrintStatus.new(run: run), layout: false)
      )
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 broadcast must not break emitter
      Rails.logger.warn("[label_print] status broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
