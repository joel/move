# frozen_string_literal: true

module RecognitionRuns
  # Restores the Apartment tenant (jobs never inherit request Current/tenant) and
  # runs the recognition pipeline for one run. Idempotent-ish: a run already past
  # `queued`/`processing` is skipped.
  class ProcessJob < ApplicationJob
    queue_as :default

    def perform(recognition_run_id, tenant:)
      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        run = RecognitionRun.find_by(id: recognition_run_id)
        return if run.nil? || run.terminal?

        RecognitionRuns::Process.new.call(run: run)
      end
    end
  end
end
