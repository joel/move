class AddCascadeToUserAuthForeignKeys < ActiveRecord::Migration[8.1]
  # Rodauth-owned tables foreign-key to users but were created without
  # ON DELETE CASCADE, so destroying a user with any verification / email-auth /
  # remember / webauthn rows raised ActiveRecord::InvalidForeignKey (HTTP 500).
  # user_omniauth_identities already cascades. Mirror that for the rest so a user
  # can be deleted in one step. Keyed by their FK column on users.
  CASCADE_FKS = {
    user_verification_keys: :id,
    user_email_auth_keys: :id,
    user_remember_keys: :id,
    user_webauthn_user_ids: :id,
    user_webauthn_keys: :user_id
  }.freeze

  def up
    CASCADE_FKS.each { |table, column| recreate_fk(table, column, on_delete: :cascade) }
  end

  def down
    CASCADE_FKS.each { |table, column| recreate_fk(table, column, on_delete: nil) }
  end

  private

  def recreate_fk(table, column, on_delete:)
    remove_foreign_key table, :users, column: column if foreign_key_exists?(table, :users, column: column)
    add_foreign_key table, :users, column: column, on_delete: on_delete
  end
end
