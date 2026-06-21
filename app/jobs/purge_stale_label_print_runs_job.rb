# frozen_string_literal: true

# Reaps old bulk label-print runs and their attached PDFs (#303) so generated
# documents don't accumulate in storage. Scheduled daily (config/recurring.yml).
# LabelPrintRun lives in each tenant schema, so this switches per Organization;
# `destroy` (not delete_all) fires the has_one_attached purge that frees the blob.
#
# RETENTION: a run's PDF is downloaded within minutes of generating, so a day-old
# run is spent. The form simply starts a fresh run if someone needs the labels again.
class PurgeStaleLabelPrintRunsJob < ApplicationJob
  RETENTION = 1.day

  def perform
    Organization.pluck(:slug).each do |slug|
      Apartment::Tenant.switch(slug) do
        LabelPrintRun.where(created_at: ..RETENTION.ago).find_each(&:destroy)
      end
    end
  end
end
