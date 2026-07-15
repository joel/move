# frozen_string_literal: true

module RecognitionRuns
  # Restores the Apartment tenant (jobs never inherit request Current/tenant) and
  # runs the recognition pipeline for one run. Idempotent-ish: a run already past
  # `queued`/`processing` is skipped (a succeeded one re-announced, see below).
  class ProcessJob < ApplicationJob
    queue_as :default

    def perform(recognition_run_id, tenant:)
      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        run = RecognitionRun.find_by(id: recognition_run_id)
        return if run.nil?
        return reannounce(run) if run.terminal?

        RecognitionRuns::Process.new.call(run: run)
      end
    end

    private

    # A terminal run reached here through a duplicate delivery or an execution
    # re-released after a crash between Process's commit and its announcement
    # (#649) — the success is durably recorded but the capture panel may never
    # have heard it and would spin forever. Re-broadcasting is idempotent (the
    # subscriber re-renders from committed state), so announce again; isolated,
    # since a side effect must not fail the job over a done run (§1#4).

    #: (untyped run) -> untyped
    def reannounce(run)
      return unless run.status == "succeeded"

      Rails.event.notify(
        "recognition_run.succeeded",
        recognition_run_id: run.id, item_count: run.metadata["item_count"].to_i
      )
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 a re-announcement must not fail the job over a done run
      Rails.logger.warn("[recognition] re-announce failed for run=#{run.id}: #{e.class}: #{e.message}")
    end
  end
end
