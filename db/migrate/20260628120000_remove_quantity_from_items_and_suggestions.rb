class RemoveQuantityFromItemsAndSuggestions < ActiveRecord::Migration[8.1]
  # Phase B: per-item quantity is removed — a moving inventory cares what's in a
  # box, not how many. Unlike fragile (Phase A), quantity is deleted outright, not
  # relocated, so there is no backfill: "Mugs x4" simply becomes "Mugs". Drop the
  # item column + the recognition suggestion's proposed value, and rebuild the
  # items Logidze trigger so it stops tracking the removed column.
  def up
    execute %(DROP TRIGGER IF EXISTS "logidze_on_items" on "items";)
    remove_column :items, :quantity
    remove_column :recognition_suggestions, :proposed_quantity
    execute items_trigger("{name, category_id}")
  end

  def down
    execute %(DROP TRIGGER IF EXISTS "logidze_on_items" on "items";)
    add_column :items, :quantity, :integer, null: false, default: 1
    add_column :recognition_suggestions, :proposed_quantity, :integer, null: false, default: 1
    execute items_trigger("{name, category_id, quantity}")
  end

  private

  def items_trigger(columns)
    <<~SQL.squish
      CREATE TRIGGER "logidze_on_items"
      BEFORE UPDATE OR INSERT ON "items" FOR EACH ROW
      WHEN (coalesce(current_setting('logidze.disabled', true), '') <> 'on')
      EXECUTE PROCEDURE logidze_logger(null, 'updated_at', '#{columns}', true);
    SQL
  end
end
