class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid, if_not_exists: true do |t|
      t.string :name

      t.timestamps
    end
  end
end
