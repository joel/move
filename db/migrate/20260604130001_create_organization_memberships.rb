# frozen_string_literal: true

class CreateOrganizationMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :organization_memberships, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :organization, type: :uuid, null: false, index: false,
                                  foreign_key: { on_delete: :cascade }
      t.references :user, type: :uuid, null: false, index: false,
                          foreign_key: { on_delete: :cascade }
      # Account admin manages Organization settings/invitations. Not a Move role.
      t.boolean :account_admin, null: false, default: false

      t.timestamps
    end

    add_index :organization_memberships, %i[organization_id user_id], unique: true
    add_index :organization_memberships, %i[user_id organization_id]
  end
end
