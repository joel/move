class BackfillItemSearchDocuments < ActiveRecord::Migration[8.1]
  # D8 data backfill: items that existed before the projection are otherwise
  # omitted from search (it inner-joins item_search_documents) until each is
  # edited. Build the lexical projection (search_text → generated tsvector) for
  # every item in plain SQL — self-contained (no app classes / no embedder calls)
  # and run per tenant via Apartment's db:migrate. Embeddings stay NULL and are
  # generated later (next item edit, or `rake search:reindex`); lexical/trigram
  # search works without them.
  def up
    return unless table_exists?(:items) && table_exists?(:item_search_documents)

    execute(<<~SQL.squish)
      INSERT INTO item_search_documents (id, item_id, move_id, search_text, created_at, updated_at)
      SELECT gen_random_uuid(), i.id, i.move_id,
        btrim(regexp_replace(concat_ws(' ',
          i.name,
          c.name,
          (SELECT string_agg(t.name, ' ') FROM item_tags it JOIN tags t ON t.id = it.tag_id
           WHERE it.item_id = i.id),
          'Box ' || b.number,
          r.name
        ), '\\s+', ' ', 'g')),
        now(), now()
      FROM items i
      JOIN boxes b ON b.id = i.box_id
      LEFT JOIN categories c ON c.id = i.category_id
      LEFT JOIN rooms r ON r.id = b.room_id
      WHERE NOT EXISTS (SELECT 1 FROM item_search_documents d WHERE d.item_id = i.id)
    SQL
  end

  def down
    # Non-destructive backfill — the projection is app-managed; nothing to undo.
  end
end
