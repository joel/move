class CreateOrganizations < ActiveRecord::Migration[8.1]
  def change
    create_table :organizations, id: :uuid, if_not_exists: true do |t|
      t.citext :slug, null: false
      t.string :name, null: false

      t.timestamps
    end
    add_index :organizations, :slug, unique: true
  end
end
