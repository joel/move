# frozen_string_literal: true

# The per-tenant sweep idiom (#584): run a block once inside every
# Organization's tenant schema. The shared home for what the recurring
# maintenance jobs and the backfill rake tasks used to copy by hand.
#
#   TenantSweep.in_each_tenant { |slug| puts "#{slug}: #{Item.count} items" }
#
# Error isolation: a slug whose schema is missing (Apartment::TenantNotFound)
# is logged and skipped, never fatal. That is the account-deletion race:
# Accounts::Delete drops the tenant schema before it deletes the Organization
# row, so the registry can briefly list a schema-less slug. Aborting there
# would starve every tenant later in the list of its sweep. Any other error
# still propagates, so a genuine bug in the block is never masked.
module TenantSweep
  # Yields each tenant slug with that tenant's schema active.
  #: () { (String) -> void } -> void
  def self.in_each_tenant
    Organization.pluck(:slug).each do |slug|
      Apartment::Tenant.switch(slug) { yield slug }
    rescue Apartment::TenantNotFound
      Rails.logger.warn("[tenant_sweep] skipped #{slug}: tenant schema not found")
    end
  end
end
