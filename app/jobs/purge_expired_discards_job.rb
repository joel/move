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
    # TenantSweep skips a slug whose schema is already dropped (the
    # account-deletion race) so one ghost tenant can't starve the rest.
    TenantSweep.in_each_tenant { Discards::PurgeExpired.new.call }
  end
end
