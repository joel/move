# frozen_string_literal: true

# Fails recognition runs stranded in queued/processing (#871) so a lost job
# can't leave a photo in flight for ever. Scheduled every 10 minutes
# (config/recurring.yml). RecognitionRun lives in each tenant schema, so this
# switches per Organization; RecognitionRuns::FailStale owns the staleness
# window and the guarded write.
class FailStaleRecognitionRunsJob < ApplicationJob
  #: () -> void
  def perform
    # TenantSweep skips a slug whose schema is already dropped (the
    # account-deletion race) so one ghost tenant can't starve the rest.
    TenantSweep.in_each_tenant { RecognitionRuns::FailStale.new.call }
  end
end
