# frozen_string_literal: true

# Fails label-print runs stranded in processing (#985) so a job that died
# before it could mark its run failed can't leave the status page spinning
# for ever: the run turns failed and the page offers "Try again". Scheduled
# every 10 minutes (config/recurring.yml). LabelPrintRun lives in each tenant
# schema, so this switches per Organization; LabelPrintRuns::FailStale owns
# the staleness window and the guarded write.
class FailStaleLabelPrintRunsJob < ApplicationJob
  #: () -> void
  def perform
    # TenantSweep skips a slug whose schema is already dropped (the
    # account-deletion race) so one ghost tenant can't starve the rest.
    TenantSweep.in_each_tenant { LabelPrintRuns::FailStale.new.call }
  end
end
