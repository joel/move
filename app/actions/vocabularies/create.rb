# frozen_string_literal: true

module Vocabularies
  # Adds a value to one of a Move's managed vocabularies (category / tag / room).
  # The kind is described by a Vocabulary registry object so one action serves
  # all three. The caller owns the tenant context and the admin / writable-Move
  # guard (controller + VocabularyPolicy).
  class Create < BaseAction
    def call(move:, vocabulary:, params:, actor:)
      yield ensure_writable(move)
      record = yield with_responsible(actor) { persist(move, vocabulary, params) }
      yield emit_event(record, vocabulary, actor)
      Success(record)
    end

    private

    def persist(move, vocabulary, params)
      record = vocabulary.records(move).new(params.slice(*vocabulary.permitted_params))
      record.save!
      Success(record)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    rescue ActiveRecord::RecordNotUnique
      # Two admins adding the same name can both pass the model uniqueness check;
      # the DB lower(name) index catches the loser — surface it as a taken name,
      # not a 500.
      record.errors.add(:name, :taken)
      Failure(record.errors)
    end

    def emit_event(record, vocabulary, actor)
      Rails.event.notify(
        "vocabulary.created",
        kind: vocabulary.kind, record_id: record.id, move_id: record.move_id, actor_id: actor&.id
      )
      Success()
    end
  end
end
