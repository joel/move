class AddLabelsPerBoxToMoves < ActiveRecord::Migration[8.1]
  def change
    # How many identical exterior labels to print per box (E1 / #303). Editable per
    # Move in Settings; defaults to 2 (lid + side) to preserve the prior fixed count
    # (was BoxLabelsPdf::PAGE_COUNT). Bounded 1..10 in the model.
    add_column :moves, :labels_per_box, :integer, null: false, default: 2
  end
end
