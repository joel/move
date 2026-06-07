# frozen_string_literal: true

module Vocabularies
  # Renames a vocabulary value (and, for tags, edits its applies-to facet).
  # Because items / boxes reference the value by foreign key, a rename is a
  # single column update that propagates to every associated record immediately
  # (Domain §4.5–4.7) — no cascade needed.
  class Update < BaseAction
    def call(record:, vocabulary:, params:, actor:)
      yield persist(record, vocabulary, params)
      yield emit_event(record, vocabulary, actor)
      Success(record)
    end

    private

    def persist(record, vocabulary, params)
      record.update!(params.slice(*vocabulary.permitted_params))
      Success(record)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
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
