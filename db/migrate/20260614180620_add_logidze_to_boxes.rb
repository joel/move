class AddLogidzeToBoxes < ActiveRecord::Migration[8.1]
  def change
    add_column :boxes, :log_data, :jsonb

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER "logidze_on_boxes"
          BEFORE UPDATE OR INSERT ON "boxes" FOR EACH ROW
          WHEN (coalesce(current_setting('logidze.disabled', true), '') <> 'on')
          -- Parameters: history_size_limit (integer), timestamp_column (text), filtered_columns (text[]),
          -- include_columns (boolean), debounce_time_ms (integer), detached_loggable_type(text), log_data_table_name(text)
          EXECUTE PROCEDURE logidze_logger(null, 'updated_at', '{number, room_id, length_cm, width_cm, height_cm, weight_kg}', true);

        SQL
      end

      dir.down do
        execute <<~SQL
          DROP TRIGGER IF EXISTS "logidze_on_boxes" on "boxes";
        SQL
      end
    end
    reversible do |dir|
      dir.up do

          execute <<~SQL
            UPDATE "boxes" as t
            SET log_data = logidze_snapshot(to_jsonb(t), 'updated_at', '{number, room_id, length_cm, width_cm, height_cm, weight_kg}', true);
          SQL

      end
    end
  end
end
