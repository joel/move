class AddFragileToBoxes < ActiveRecord::Migration[8.1]
  def change
    add_column :boxes, :fragile, :boolean, null: false, default: false
  end
end
