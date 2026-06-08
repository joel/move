# frozen_string_literal: true

module Search
  # (Re)builds an Item's search projection (Domain §7.3; Technical Foundation
  # §11). Composes the denormalized search_text from the item's own metadata plus
  # its box number / room (so a query can match on context), upserts the
  # ItemSearchDocument (the generated tsvector follows the text), and regenerates
  # the embedding from that text only — never the image (Domain §7.5). A nil
  # embedding is fine: lexical/trigram search still works (graceful degradation).
  class RefreshDocument < BaseAction
    def call(item:, embedder: EmbeddingProviders.resolve)
      doc = yield persist(item, embedder)
      Success(doc)
    end

    private

    def persist(item, embedder)
      doc = item.search_document || item.build_search_document(move: item.move)
      doc.search_text = compose_text(item)
      apply_embedding(doc, embedder)
      doc.save!
      Success(doc)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def apply_embedding(doc, embedder)
      vector = embedder.embed(doc.search_text).then { |r| [r.vector, r.model] }
      doc.embedding, model = vector
      doc.embedding_model = doc.embedding ? model : nil
      doc.embedded_at = doc.embedding ? Time.current : nil
    end

    # Textual metadata only: name + category + tags + box number + room.
    def compose_text(item)
      box = item.box
      [
        item.name,
        item.category&.name,
        item.tags.map(&:name),
        ("Box #{box.number}" if box),
        box&.room&.name
      ].flatten.compact_blank.join(" ")
    end
  end
end
