class AddAutoConfirmThresholdToMoves < ActiveRecord::Migration[8.1]
  def change
    # Recognition confidence at/above this auto-confirms a suggestion into an item
    # (Domain §5.4). Editable per Move in Settings (D13); defaults to 0.8.
    add_column :moves, :auto_confirm_threshold, :decimal, precision: 3, scale: 2,
                                                          null: false, default: 0.8
  end
end
