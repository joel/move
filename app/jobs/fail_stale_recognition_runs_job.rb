# frozen_string_literal: true

# Fails recognition runs stranded in queued/processing (#871) so a lost job
# can't leave a photo in flight for ever. Scheduled every 10 minutes
# (config/recurring.yml). RecognitionRun lives in each tenant schema, so this
# switches per Organization; RecognitionRuns::FailStale owns the staleness
# window and the guarded write.
class FailStaleRecognitionRunsJob < ApplicationJob
  #: () -> void
  def perform
    Organization.pluck(:slug).each do |slug|
      Apartment::Tenant.switch(slug) { RecognitionRuns::FailStale.new.call }
    rescue Apartment::TenantNotFound
      # Account-deletion race (the PurgeExpiredDiscardsJob precedent): the
      # schema is dropped before the Organization row, so skip a schema-less
      # slug rather than starve every tenant later in the list.
      next
    end
  end
end
