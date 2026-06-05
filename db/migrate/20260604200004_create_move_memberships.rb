class CreateMoveMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :move_memberships, id: :uuid, if_not_exists: true do |t|
      # Same-schema FK: move_memberships and moves are cloned together per tenant.
      t.references :move, null: false, foreign_key: true, type: :uuid
      # References public.users; no cross-schema FK.
      t.uuid :user_id, null: false
      t.string :role, null: false, default: "member"

      t.timestamps
    end
    add_index :move_memberships, %i[move_id user_id], unique: true
    add_index :move_memberships, :user_id
  end
end
