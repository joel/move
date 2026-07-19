# frozen_string_literal: true

# Reaps old insurance claim-dossier runs and their attached PDFs (#702) so
# generated documents don't accumulate in storage — the dossier doubly so, since
# the file itself is sensitive (locations + photos). Scheduled daily
# (config/recurring.yml), mirroring PurgeStaleLabelPrintRunsJob (#305).
# InsuranceDossierRun lives in each tenant schema, so this switches per
# Organization; `destroy` (not delete_all) fires the has_one_attached purge that
# frees the blob.
#
# Reaped only when **terminal** AND finished_at is past the retention window —
# never a queued/processing run (a Solid Queue backlog could otherwise leave a
# run non-terminal past the window, and deleting it + its attachment would
# strand a waiting user). Keying off finished_at (not created_at) means a run
# that sat in a long queue still gets its full window after finishing.
class PurgeStaleInsuranceDossierRunsJob < ApplicationJob
  RETENTION = 1.day

  def perform
    Organization.pluck(:slug).each do |slug|
      Apartment::Tenant.switch(slug) do
        InsuranceDossierRun.where(status: InsuranceDossierRun::TERMINAL, finished_at: ..RETENTION.ago)
                           .find_each(&:destroy)
      end
    rescue Apartment::TenantNotFound
      # Account-deletion race: Accounts::Delete drops the tenant schema before it
      # deletes the Organization row, so a listed slug can have no schema. Skip —
      # aborting here would silently starve every tenant later in the list.
      next
    end
  end
end
