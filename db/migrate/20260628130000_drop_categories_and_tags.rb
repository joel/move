class DropCategoriesAndTags < ActiveRecord::Migration[8.1]
  # Phase C: per-item category and tags are removed (a moving inventory cares
  # what's in a box, not a per-object taxonomy). Drop the join + the two managed
  # vocabularies and their references, and rebuild the items Logidze trigger so it
  # only tracks `name`. Rooms remain the sole managed vocabulary.
  #
  # Irreversible: these three tables were built up across five migrations (create
  # + discard columns + Logidze triggers + the case-insensitive lower(name)
  # indexes + the tag applies_to facet); a `down` that recreated them would be a
  # lossy, drift-prone replica and would not restore the dropped data. Recover by
  # reverting the PR and restoring from backup, not by `db:rollback`.
  def up
    drop_table :item_tags
    remove_reference :items, :category, foreign_key: true
    remove_reference :recognition_suggestions, :proposed_category,
                     foreign_key: { to_table: :categories }
    drop_table :tags
    drop_table :categories

    execute %(DROP TRIGGER IF EXISTS "logidze_on_items" on "items";)
    execute <<~SQL.squish
      CREATE TRIGGER "logidze_on_items"
      BEFORE UPDATE OR INSERT ON "items" FOR EACH ROW
      WHEN (coalesce(current_setting('logidze.disabled', true), '') <> 'on')
      EXECUTE PROCEDURE logidze_logger(null, 'updated_at', '{name}', true);
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
