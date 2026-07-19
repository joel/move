# frozen_string_literal: true

module InsuranceDossierRuns
  # Pushes the live dossier status component to every subscriber of a run's
  # progress stream (#702), so the bar advances and the "Download" appears
  # without a reload. Mirrors LabelPrintRuns::Broadcasting (#303).
  # `module_function` so it is callable both standalone (from GenerateJob) and
  # when mixed into an action.
  module Broadcasting
    module_function

    # A broadcast must never break its emitter (AGENTS.md §1 #4): this runs
    # synchronously inside RecordProgress and inside GenerateJob. A render or
    # backend failure here must not fail the job — the worst case is a missed
    # live update; the next progress event (or the run show page on load)
    # re-renders the correct state.

    #: (untyped run) -> void
    def broadcast_status(run)
      Turbo::StreamsChannel.broadcast_replace_to(
        run, :progress,
        target: Components::Ui::InsuranceDossierStatus::ID,
        html: ApplicationController.render(Components::Ui::InsuranceDossierStatus.new(run: run), layout: false)
      )
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 broadcast must not break emitter
      Rails.logger.warn("[insurance] status broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
