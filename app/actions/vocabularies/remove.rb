# frozen_string_literal: true

module Vocabularies
  # Removes a vocabulary value, detaching it from every record that used it
  # (Domain §4.5–4.7). Detachment is handled by the model's `dependent:` —
  # categories and rooms nullify their items/boxes; a tag destroys its item_tags
  # join rows (the items themselves survive). The whole thing runs in one
  # transaction so a value is never half-detached. The in-use *confirmation* is
  # the caller's responsibility (UI turbo-confirm); this action assumes it has
  # already been granted.
  class Remove < BaseAction
    include Search::Reindexing

    def call(record:, vocabulary:, actor:)
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

    # How many records the value was attached to (reported back to the user).
    def usage_count(record)
      case record
      when Category, Tag then record.items.count
      when Room then record.boxes.count
      else 0
      end
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
