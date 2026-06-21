# frozen_string_literal: true

# Reaps old bulk label-print runs and their attached PDFs (#303) so generated
# documents don't accumulate in storage. Scheduled daily (config/recurring.yml).
# LabelPrintRun lives in each tenant schema, so this switches per Organization;
# `destroy` (not delete_all) fires the has_one_attached purge that frees the blob.
#
# RETENTION: a run's PDF is downloaded within minutes of generating, so a day-old
# run is spent. The form simply starts a fresh run if someone needs the labels again.
#
# Only **terminal** runs are reaped — never a queued/processing one. A Solid Queue
# backlog could otherwise leave a run non-terminal past the retention window, and
# deleting it (plus its attachment) would strand a user still waiting on it (#305).
class PurgeStaleLabelPrintRunsJob < ApplicationJob
  RETENTION = 1.day

  def perform
    Organization.pluck(:slug).each do |slug|
      Apartment::Tenant.switch(slug) do
        LabelPrintRun.where(status: LabelPrintRun::TERMINAL, created_at: ..RETENTION.ago)
                     .find_each(&:destroy)
      end
    end
  end
end
