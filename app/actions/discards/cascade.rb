# frozen_string_literal: true

module Discards
  # Soft-deletes a record and every descendant declared via `discard_cascade_to`,
  # stamping them all with one fresh `discard_batch_id` (Technical Foundation §9).
  # Children are snapshotted before discarding so the walk is stable, and only
  # `kept` children join the batch — a child discarded earlier keeps its own batch
  # and is therefore left out of this cascade's eventual restore. The whole tree is
  # discarded in a single transaction. Returns the batch id on success.
  class Cascade < BaseAction
    #: (record: untyped, actor: untyped, ?source: Symbol) -> Dry::Monads::Result[untyped, untyped]
    def call(record:, actor:, source: :web) # rubocop:disable Lint/UnusedMethodArgument
      yield ensure_writable(record.move)
      batch_id = SecureRandom.uuid
      ActiveRecord::Base.transaction do
        discard_node(record, batch_id: batch_id, parent: nil)
      end
      Success(batch_id)
    rescue ActiveRecord::RecordInvalid, Discard::RecordNotDiscarded => e
      Failure(e.message)
    end

    private

    #: (untyped record, batch_id: untyped, parent: untyped) -> untyped
    def discard_node(record, batch_id:, parent:)
      record.class.discard_cascade_associations.each do |assoc|
        record.public_send(assoc).kept.to_a.each do |child|
          discard_node(child, batch_id: batch_id, parent: record)
        end
      end
      record.discard_in_batch!(batch_id: batch_id, parent: parent)
    end
  end
end
