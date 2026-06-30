# frozen_string_literal: true

# pack_public: true -- public API of packs/vocabularies: updates a vocabulary entry (VocabulariesController).
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Vocabularies
  # Renames a vocabulary value (rooms — the only managed vocabulary left). Because
  # boxes reference the room by foreign key, a rename is a single column update
  # that propagates to every associated box immediately (Domain §4.5–4.7) — no
  # cascade needed. A rename changes the items' denormalized search_text (box room
  # is part of it), so the affected items are reindexed.
  class Update < BaseAction
    include Search::Reindexing

    def call(record:, vocabulary:, params:, actor:)
      yield ensure_writable(record.move)
      affected = affected_item_ids(record) # before rename
      yield with_responsible(actor) { persist(record, vocabulary, params) }
      reindex_items(affected) if record.saved_change_to_name?
      yield emit_event(record, vocabulary, actor)
      Success(record)
    end

    private

    def persist(record, vocabulary, params)
      record.update!(params.slice(*vocabulary.permitted_params))
      Success(record)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    rescue ActiveRecord::RecordNotUnique
      # Mirror Create: a concurrent rename to the same name trips the DB
      # lower(name) index — report a taken name instead of a 500.
      record.errors.add(:name, :taken)
      Failure(record.errors)
    end

    def emit_event(record, vocabulary, actor)
      Rails.event.notify(
        "vocabulary.updated",
        kind: vocabulary.kind, record_id: record.id, move_id: record.move_id, actor_id: actor&.id
      )
      Success()
    end
  end
end
