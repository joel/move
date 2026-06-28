# frozen_string_literal: true

module Search
  # (Re)builds an Item's search projection (Domain §7.3; Technical Foundation
  # §11). Composes the denormalized search_text from the item's own metadata plus
  # its box number / room (so a query can match on context), upserts the
  # ItemSearchDocument (the generated tsvector follows the text), and regenerates
  # the embedding from that text only — never the image (Domain §7.5). A nil
  # embedding is fine: lexical/trigram search still works (graceful degradation).
  class RefreshDocument < BaseAction
    # The embedder defaults to the item's Move's own provider (#232 — per-Move
    # BYO): a Move on openai with a key embeds with its key, every other Move
    # gets the network-free Fake. Stored item vectors therefore always share the
    # Move's current vector space, matching the query vector Search::Items builds.
    def call(item:, embedder: nil)
      embedder ||= EmbeddingProviders.for_move(item.move)
      doc = yield persist(item, embedder)
      Success(doc)
    end

    private

    def persist(item, embedder)
      write(item.search_document || item.build_search_document(move: item.move), item, embedder)
    rescue ActiveRecord::RecordNotUnique
      # A concurrent refresh inserted the row first (one doc per item) — reload
      # the winner's row and update it so duplicate jobs converge instead of one
      # being dropped.
      #
      # find_by! (not .sole / find_sole_by): the DB unique index on item_id
      # already guarantees ≤1 row, so .sole's "more than one?" assertion is dead
      # code here and costs an extra LIMIT-2 probe. find_by! is the idiomatic
      # "fetch the existing unique row". (Reach for .sole when an exactly-one
      # invariant is NOT backed by a constraint.)
      write(ItemSearchDocument.find_by!(item_id: item.id), item, embedder)
    end

    def write(doc, item, embedder)
      doc.search_text = compose_text(item)
      apply_embedding(doc, embedder)
      doc.save!
      Success(doc)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # A provider failure (missing key, timeout, API error) must NOT lose the
    # lexical projection — leave the embedding nil and persist search_text, so the
    # item stays searchable lexically/trigram (graceful degradation, Domain §7.3).
    def apply_embedding(doc, embedder)
      result = embedder.embed(doc.search_text)
      doc.embedding = result.vector
      doc.embedding_model = result.vector ? result.model : nil
      doc.embedded_at = result.vector ? Time.current : nil
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §7.3 keep item lexically searchable
      Rails.logger.warn("[search] embedding failed for item=#{doc.item_id}: #{e.class}: #{e.message}")
      doc.embedding = nil
      doc.embedding_model = nil
      doc.embedded_at = nil
    end

    # Textual metadata only: name + box number + room.
    def compose_text(item)
      box = item.box
      [
        item.name,
        ("Box #{box.number}" if box),
        box&.room&.name
      ].compact_blank.join(" ")
    end
  end
end
