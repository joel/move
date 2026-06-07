# frozen_string_literal: true

module Vocabularies
  # Renames a vocabulary value (and, for tags, edits its applies-to facet).
  # Because items / boxes reference the value by foreign key, a rename is a
  # single column update that propagates to every associated record immediately
  # (Domain §4.5–4.7) — no cascade needed.
  #
  # Narrowing a tag to `box`-only is the one case that needs more than a column
  # write: the tag can no longer apply to items (Tag.for_items), so its existing
  # item associations are detached in the **same transaction** — otherwise items
  # would keep a hidden, unselectable tag that silently vanishes on their next
  # save.
  class Update < BaseAction
    def call(record:, vocabulary:, params:, actor:)
      detached = yield persist(record, vocabulary, params)
      yield emit_event(record, vocabulary, actor, detached)
      Success(record)
    end

    private

    def persist(record, vocabulary, params)
      detached = 0
      ActiveRecord::Base.transaction do
        record.update!(params.slice(*vocabulary.permitted_params))
        detached = detach_item_tags(record)
      end
      Success(detached)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    # Drop a now-box-only tag's item associations (the items survive). Returns the
    # number of item links removed; 0 for any other vocabulary or facet change.
    def detach_item_tags(record)
      return 0 unless record.is_a?(Tag) && record.applies_to == "box"

      count = record.item_tags.count
      record.item_tags.destroy_all
      count
    end

    def emit_event(record, vocabulary, actor, detached)
      Rails.event.notify(
        "vocabulary.updated",
        kind: vocabulary.kind, record_id: record.id, move_id: record.move_id,
        actor_id: actor&.id, detached_item_count: detached
      )
      Success()
    end
  end
end
