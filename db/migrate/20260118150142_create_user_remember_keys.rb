class CreateUserRememberKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :user_remember_keys, id: false do |t|
      t.uuid :id, primary_key: true
      t.foreign_key :users, column: :id
      t.string :key, null: false
      t.datetime :deadline, null: false
    end
  end
end
