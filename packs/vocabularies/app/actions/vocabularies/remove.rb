# frozen_string_literal: true

module Vocabularies
  # Removes a vocabulary value (rooms), detaching it from every box that used it
  # (Domain §4.5–4.7). Detachment is handled by the model's `dependent: :nullify`
  # (boxes keep existing, room_id cleared). Runs in one transaction so a value is
  # never half-detached. The in-use *confirmation* is the caller's responsibility
  # (UI turbo-confirm); this action assumes it has already been granted.
  class Remove < BaseAction
    include Search::Reindexing

    def call(record:, vocabulary:, actor:)
      yield ensure_writable(record.move)
      affected = affected_item_ids(record) # before detach/destroy
      detached = yield destroy(record)
      reindex_items(affected) # rebuild search_text without the removed value
      yield emit_event(record, vocabulary, actor, detached)
      Success(detached)
    end

    private

    def destroy(record)
      detached = nil
      ActiveRecord::Base.transaction do
        detached = usage_count(record)
        record.destroy!
      end
      Success(detached)
    rescue ActiveRecord::RecordNotDestroyed => e
      Failure(e.record.errors)
    end

    # How many boxes the room was attached to (reported back to the user).
    def usage_count(record)
      record.boxes.count
    end

    def emit_event(record, vocabulary, actor, detached)
      Rails.event.notify(
        "vocabulary.removed",
        kind: vocabulary.kind, record_id: record.id, move_id: record.move_id,
        actor_id: actor&.id, detached_count: detached
      )
      Success()
    end
  end
end
