# frozen_string_literal: true

class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :name, null: false
      # Globally unique subdomain label (citext → case-insensitive lookup).
      t.citext :slug, null: false
      t.jsonb :settings, null: false, default: {}
      t.uuid :created_by_user_id

      t.timestamps
    end

    add_index :organizations, :slug, unique: true
    add_foreign_key :organizations, :users, column: :created_by_user_id, on_delete: :nullify
  end
end
