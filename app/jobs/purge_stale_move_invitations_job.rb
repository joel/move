# frozen_string_literal: true

# Reaps terminal Move invitations (Phase D14, #608) — accepted, revoked, or
# expired-unaccepted rows past MoveInvitation::RETENTION — so the public-schema
# table does not grow unbounded. The activity feed keeps the durable audit
# trail. Scheduled daily (config/recurring.yml). MoveInvitation is an excluded
# Apartment model (public only), so this runs once, not per tenant.
#
# `delete_all` is correct here: the rows carry no attachments or callbacks, and
# a terminal invitation is never read again.
class PurgeStaleMoveInvitationsJob < ApplicationJob
  def perform
    MoveInvitation.purgeable.delete_all
  end
end
