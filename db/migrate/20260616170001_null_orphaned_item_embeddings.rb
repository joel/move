# frozen_string_literal: true

# #232 one-off data migration. Existing item vectors were computed under the
# app-wide OPENAI_API_KEY (openai vector space). After this migration every Move
# defaults to embedding_provider: "fake", whose query vectors live in a different
# space — so the stored vectors become orphaned and would poison cosine ranking.
# Null them all: search cleanly falls back to lexical + trigram until a Move opts
# into "openai" (which enqueues a per-Move reindex that recomputes the vectors
# with the Move's own key) or an item is next edited (recomputed in the Move's
# current space). Cheap, correct, and avoids a half-migrated vector space.
#
# Self-contained plain SQL (no app classes), run per tenant via Apartment's
# enhanced db:migrate — the same pattern as BackfillItemSearchDocuments.
class NullOrphanedItemEmbeddings < ActiveRecord::Migration[8.1]
  def up
    return unless table_exists?(:item_search_documents)

    execute(<<~SQL.squish)
      UPDATE item_search_documents
      SET embedding = NULL, embedding_model = NULL, embedded_at = NULL
      WHERE embedding IS NOT NULL
    SQL
  end

  def down
    # Irreversible: the orphaned vectors are intentionally discarded. They are
    # app-regenerated (next item edit / reindex), so there is nothing to restore.
  end
end
