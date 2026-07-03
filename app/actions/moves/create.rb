# frozen_string_literal: true

module Moves
  # Creates a Move inside the active tenant schema and makes the creator its
  # admin. The caller is responsible for the tenant context (the subdomain
  # elevator switches Apartment before this runs).
  class Create < BaseAction
    #: (params: untyped, creator: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(params:, creator:)
      move = yield with_responsible(creator) { persist(params, creator) }
      yield emit_event(move)
      Success(move)
    end

    private

    #: (untyped params, untyped creator) -> Dry::Monads::Result[untyped, untyped]
    def persist(params, creator)
      move = nil #: untyped
      ActiveRecord::Base.transaction do
        move = Move.create!(params.merge(created_by: creator))
        move.move_memberships.create!(user: creator, role: "admin")
        Moves::DefaultVocabularies.apply(move)
      end
      Success(move)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    #: (untyped move) -> Dry::Monads::Success[nil]
    def emit_event(move)
      Rails.event.notify("move.created", move_id: move.id)
      Success()
    end
  end
end
