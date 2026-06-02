class CreateUserOmniauthIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :user_omniauth_identities, id: :uuid do |t|
      t.references :user, type: :uuid, null: false,
                          foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :uid, null: false
    end

    add_index :user_omniauth_identities,
              %i[provider uid],
              unique: true,
              name: "idx_omniauth_identities_uniqueness"
  end
end
