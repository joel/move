class CreateItemSearchDocuments < ActiveRecord::Migration[8.1]
  # D8 hybrid search projection (Technical Foundation §11.2–11.3). One row per
  # Item, holding the denormalized search_text, a generated tsvector for
  # full-text, and an optional pgvector embedding for semantic search. Lives in
  # the tenant schema like every Move-owned record, so it is scoped by move_id
  # (org == schema under Apartment).
  def up
    ensure_pgvector_available!
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")
    enable_extension "vector" unless extension_enabled?("vector")

    create_table :item_search_documents, id: :uuid do |t|
      t.references :item, type: :uuid, null: false,
                          foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :move, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.text :search_text, null: false, default: ""
      t.virtual :search_tsvector, type: :tsvector,
                                  as: "to_tsvector('english', coalesce(search_text, ''))", stored: true
      t.column :embedding, "vector(1536)" # nullable — lexical works without it
      t.string :embedding_model
      t.datetime :embedded_at
      t.timestamps
    end

    add_index :item_search_documents, :search_tsvector, using: :gin
    add_index :item_search_documents, :search_text, using: :gin, opclass: :gin_trgm_ops,
                                                    name: "index_item_search_documents_on_search_text_trgm"
    # Approximate-nearest-neighbour index for cosine semantic search.
    execute <<~SQL.squish
      CREATE INDEX index_item_search_documents_on_embedding
      ON item_search_documents USING hnsw (embedding vector_cosine_ops)
    SQL
  end

  def down
    drop_table :item_search_documents
  end

  private

  # D8 is a coordinated infra change: the DB accessory must be cut over to
  # `pgvector/pgvector:pg18` BEFORE this migration runs (a normal app deploy runs
  # db:migrate but does NOT reboot the accessory). If pgvector isn't installed,
  # fail fast with the runbook instead of a cryptic `CREATE EXTENSION` error —
  # the operator cuts the accessory over (new-app-recipe.md §cutover) then redeploys.
  def ensure_pgvector_available!
    return if extension_available?("vector")

    raise <<~MSG.squish
      pgvector is not installed on this PostgreSQL server. D8 requires the
      `pgvector/pgvector:pg18` image — cut the DB accessory over FIRST
      (`kamal accessory ...`, see doc/project/new-app-recipe.md §cutover),
      then redeploy. This migration was aborted before any schema change.
    MSG
  end

  def extension_available?(name)
    select_value(
      ActiveRecord::Base.sanitize_sql_array(["SELECT 1 FROM pg_available_extensions WHERE name = ?", name])
    ).present?
  end
end
