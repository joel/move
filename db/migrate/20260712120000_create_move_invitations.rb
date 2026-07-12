# frozen_string_literal: true

# Email invitations to a Move (Phase D14, #608). Lives in `public` (an excluded
# Apartment model, like SessionHandoffToken) because the accept flow runs on the
# apex host, where no tenant is active — the emailed token must resolve before
# the invitee can reach any tenant. `move_id` references a tenant-schema Move
# across schemas, so no DB foreign key (mirrors move_memberships.user_id in the
# other direction). Only the SHA-256 digest of the invite token is persisted;
# the raw value travels once, in the invitation email.
class CreateMoveInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :move_invitations, id: :uuid, if_not_exists: true do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      # Tenant-schema Move — cross-schema reference, no FK.
      t.uuid :move_id, null: false
      # citext: one identity per mailbox regardless of case (create, pending
      # uniqueness, and the accept-time email binding all compare through it).
      t.citext :email, null: false
      # MoveMembership role granted on acceptance (admin/contributor/viewer).
      t.string :role, null: false, default: "contributor"
      # The admin who invited; kept for the landing-page copy and the activity
      # trail. Nullified if that user deletes their account.
      t.uuid :invited_by_id
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at

      t.timestamps
    end
    add_foreign_key :move_invitations, :users, column: :invited_by_id, on_delete: :nullify,
                                               if_not_exists: true
    add_index :move_invitations, :token_digest, unique: true, if_not_exists: true
    # One live invitation per (move, email); accepted/revoked rows don't block a
    # fresh invite later.
    add_index :move_invitations, %i[move_id email], unique: true,
                                                    where: "accepted_at IS NULL AND revoked_at IS NULL",
                                                    name: "index_move_invitations_pending_uniqueness",
                                                    if_not_exists: true
    # Sweep expired rows efficiently.
    add_index :move_invitations, :expires_at, if_not_exists: true
    add_index :move_invitations, :invited_by_id, if_not_exists: true
  end
end
