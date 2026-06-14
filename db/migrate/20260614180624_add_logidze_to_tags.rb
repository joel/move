class AddLogidzeToTags < ActiveRecord::Migration[8.1]
  def change
    add_column :tags, :log_data, :jsonb

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER "logidze_on_tags"
          BEFORE UPDATE OR INSERT ON "tags" FOR EACH ROW
          WHEN (coalesce(current_setting('logidze.disabled', true), '') <> 'on')
          -- Parameters: history_size_limit (integer), timestamp_column (text), filtered_columns (text[]),
          -- include_columns (boolean), debounce_time_ms (integer), detached_loggable_type(text), log_data_table_name(text)
          EXECUTE PROCEDURE logidze_logger(null, 'updated_at', '{name, applies_to}', true);

        SQL
      end

      dir.down do
        execute <<~SQL
          DROP TRIGGER IF EXISTS "logidze_on_tags" on "tags";
        SQL
      end
    end
    reversible do |dir|
      dir.up do

          execute <<~SQL
            UPDATE "tags" as t
            SET log_data = logidze_snapshot(to_jsonb(t), 'updated_at', '{name, applies_to}', true);
          SQL

      end
    end
  end
end
