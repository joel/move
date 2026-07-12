# frozen_string_literal: true

# D14 (#608): move_invitations.organization_id was created with a restrictive
# FK (no on_delete). Invitations can linger (pending indefinitely, terminal for
# 30 days), so deleting a solo Organization — as Accounts::Delete does after it
# has already dropped the tenant schema — would fail with InvalidForeignKey,
# leaving a half-torn-down account. Organization owns its invitations, so the
# FK cascades (matching organization_memberships' dependent: :destroy). A
# DB-level cascade rather than a Ruby association because packs/organizations
# must not depend on packs/move_invitations (Packwerk cycle).
class CascadeMoveInvitationsOnOrganizationDelete < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :move_invitations, :organizations
    add_foreign_key :move_invitations, :organizations, on_delete: :cascade
  end

  def down
    remove_foreign_key :move_invitations, :organizations
    add_foreign_key :move_invitations, :organizations
  end
end
