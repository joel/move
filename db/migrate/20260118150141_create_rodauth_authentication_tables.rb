class CreateRodauthAuthenticationTables < ActiveRecord::Migration[8.1]
  def change
    create_table :user_verification_keys, id: false do |t|
      t.uuid :id, primary_key: true
      t.foreign_key :users, column: :id
      t.string :key, null: false
      t.datetime :requested_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :email_last_sent, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    create_table :user_email_auth_keys, id: false do |t|
      t.uuid :id, primary_key: true
      t.foreign_key :users, column: :id
      t.string :key, null: false
      t.datetime :deadline, null: false
      t.datetime :email_last_sent, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    create_table :user_webauthn_user_ids, id: false do |t|
      t.uuid :id, primary_key: true
      t.foreign_key :users, column: :id
      t.string :webauthn_id, null: false
    end

    create_table :user_webauthn_keys, primary_key: %i[user_id webauthn_id] do |t|
      t.references :user, foreign_key: true, type: :uuid
      t.string :webauthn_id
      t.string :public_key, null: false
      t.integer :sign_count, null: false
      t.datetime :last_use, null: false, default: -> { "CURRENT_TIMESTAMP" }
      # Human-friendly passkey label (resolved from AAGUID / User-Agent).
      t.string :name, limit: 80
    end
  end
end
