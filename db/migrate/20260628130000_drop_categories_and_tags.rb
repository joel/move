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

    rebuild_search_projection
  end

  private

  # The search projection denormalized category/tag names into search_text (and
  # into the embedding vector). Dropping the columns doesn't touch those existing
  # rows, so without this a search could still match/rank on removed taxonomy
  # until each item is next edited. Recompute search_text the same way the new
  # Search::RefreshDocument#compose_text does (name + "Box N" + room) in plain SQL
  # — self-contained, no app classes — and null the now-stale embeddings; they
  # regenerate on the next item edit or `rake search:reindex`. Runs per tenant via
  # Apartment's db:migrate. Lexical/trigram search works without the embedding.
  def rebuild_search_projection
    return unless table_exists?(:item_search_documents)

    execute(<<~SQL.squish)
      UPDATE item_search_documents AS d
      SET search_text = btrim(regexp_replace(
            concat_ws(' ', i.name, 'Box ' || b.number, r.name), '\\s+', ' ', 'g')),
          embedding = NULL, embedding_model = NULL, embedded_at = NULL,
          updated_at = now()
      FROM items i
      JOIN boxes b ON b.id = i.box_id
      LEFT JOIN rooms r ON r.id = b.room_id
      WHERE d.item_id = i.id
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
