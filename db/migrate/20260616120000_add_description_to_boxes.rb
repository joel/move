# frozen_string_literal: true

# An optional, human-readable summary of a box's contents ("Clothes, Electronics,
# Books"). Tracked by Logidze alongside the other edited columns so an edit shows
# in the activity feed (the trigger is recreated with `description` appended to the
# include-list). The snapshot is NOT re-run: existing per-box history is preserved
# and description simply starts being tracked from the next update.
class AddDescriptionToBoxes < ActiveRecord::Migration[8.1]
  TRACKED = "{number, room_id, length_cm, width_cm, height_cm, weight_kg, description}"
  PREVIOUS = "{number, room_id, length_cm, width_cm, height_cm, weight_kg}"

  def up
    add_column :boxes, :description, :text
    recreate_logidze_trigger(TRACKED)
  end

  def down
    recreate_logidze_trigger(PREVIOUS)
    remove_column :boxes, :description
  end

  private

  def recreate_logidze_trigger(columns)
    execute <<~SQL.squish
      DROP TRIGGER IF EXISTS "logidze_on_boxes" on "boxes";
    SQL
    execute <<~SQL.squish
      CREATE TRIGGER "logidze_on_boxes"
      BEFORE UPDATE OR INSERT ON "boxes" FOR EACH ROW
      WHEN (coalesce(current_setting('logidze.disabled', true), '') <> 'on')
      EXECUTE PROCEDURE logidze_logger(null, 'updated_at', '#{columns}', true);
    SQL
  end
end
