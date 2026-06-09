class ExpandMoveMembershipRoles < ActiveRecord::Migration[8.1]
  # D11 — move-level roles grow from admin/member to admin/contributor/viewer.
  # Runs per tenant schema (Apartment enhances db:migrate).
  def up
    change_column_default :move_memberships, :role, from: "member", to: "viewer"

    # Existing "member" rows could already mutate boxes/items, so map them to
    # the behaviour-preserving tier (contributor), not the read-only viewer.
    execute(<<~SQL.squish)
      UPDATE move_memberships SET role = 'contributor' WHERE role = 'member'
    SQL
  end

  def down
    execute(<<~SQL.squish)
      UPDATE move_memberships SET role = 'member' WHERE role IN ('contributor', 'viewer')
    SQL

    change_column_default :move_memberships, :role, from: "viewer", to: "member"
  end
end
