class RemoveFragileFromItemsAndSuggestions < ActiveRecord::Migration[8.1]
  # Phase A: fragile moved off the item onto the box (boxes.fragile, a manual
  # flag). Drop the now-unused item column + the recognition suggestion's
  # proposed value, and rebuild the items Logidze trigger so it stops tracking the
  # removed column. No re-snapshot: log_data isn't in structure.sql and the feed's
  # revert reads only name/quantity/category_id, so prior history stays valid.
  def up
    execute %(DROP TRIGGER IF EXISTS "logidze_on_items" on "items";)
    remove_column :items, :fragile
    remove_column :recognition_suggestions, :proposed_fragile
    execute items_trigger("{name, category_id, quantity}")
  end

  def down
    execute %(DROP TRIGGER IF EXISTS "logidze_on_items" on "items";)
    add_column :items, :fragile, :boolean, null: false, default: false
    # Faithful revert of the original (intentionally nullable) AI-proposed column.
    add_column :recognition_suggestions, :proposed_fragile, :boolean # rubocop:disable Rails/ThreeStateBooleanColumn
    execute items_trigger("{name, category_id, quantity, fragile}")
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
