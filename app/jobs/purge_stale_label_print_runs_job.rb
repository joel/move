# frozen_string_literal: true

# Reaps old bulk label-print runs and their attached PDFs (#303) so generated
# documents don't accumulate in storage. Scheduled daily (config/recurring.yml).
# LabelPrintRun lives in each tenant schema, so this switches per Organization;
# `destroy` (not delete_all) fires the has_one_attached purge that frees the blob.
#
# RETENTION: a run's PDF is downloaded within minutes of finishing, so a run that
# finished a day ago is spent. The form simply starts a fresh run if someone needs
# the labels again.
#
# Reaped only when **terminal** AND finished_at is past the retention window — never
# a queued/processing run (a Solid Queue backlog could otherwise leave a run
# non-terminal past the window, and deleting it + its attachment would strand a
# waiting user). Keying off finished_at (not created_at) means a run that sat in a
# long queue before completing still gets its full retention window after it
# finished, rather than being reaped the moment it completes (#305).
class PurgeStaleLabelPrintRunsJob < ApplicationJob
  RETENTION = 1.day

  def perform
    Organization.pluck(:slug).each do |slug|
      Apartment::Tenant.switch(slug) do
        LabelPrintRun.where(status: LabelPrintRun::TERMINAL, finished_at: ..RETENTION.ago)
                     .find_each(&:destroy)
      end
    end
  end
end
