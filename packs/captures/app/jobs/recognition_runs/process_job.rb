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
        # A terminal run reached here through a duplicate delivery or an
        # execution re-released after a crash between Process's commit and its
        # announcement — re-announce so a lost broadcast can't strand the
        # capture panel (#649); Reannounce no-ops on failed runs.
        return RecognitionRuns::Reannounce.new.call(run: run) if run.terminal?

        RecognitionRuns::Process.new.call(run: run)
      end
    end
  end
end
