# frozen_string_literal: true

# Nightly hard-delete of soft-deleted records past Discardable::RETENTION — the
# other half of the discard/restore contract: a deleted box/item/photo is
# restorable from the activity feed for the window, then genuinely gone, blobs
# included. Scheduled daily (config/recurring.yml). Discardable rows live in each
# tenant schema, so this switches per Organization; Discards::PurgeExpired owns
# the FK ordering and per-record error isolation.
class PurgeExpiredDiscardsJob < ApplicationJob
  #: () -> void
  def perform
    Organization.pluck(:slug).each do |slug|
      Apartment::Tenant.switch(slug) { Discards::PurgeExpired.new.call }
    rescue Apartment::TenantNotFound
      # Account-deletion race: Accounts::Delete drops the tenant schema before it
      # deletes the Organization row, so a listed slug can have no schema. Skip —
      # aborting here would silently starve every tenant later in the list.
      next
    end
  end
end
