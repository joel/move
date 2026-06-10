# frozen_string_literal: true

module RecognitionSuggestions
  # Review action "Keep" (Design Spec C2): accept a suggestion as detected. The
  # suggestion is marked accepted and its Item confirmed. For a `conflict`
  # suggestion this resolves in favour of the existing confirmed item (which is
  # already confirmed — the update is idempotent and no duplicate is created).
  # Caller owns the tenant context + writable-Move guard (controller).
  class Keep < BaseAction
    def call(suggestion:, actor:)
      yield ensure_writable(suggestion.move)
      yield persist(suggestion)
      yield emit_event(suggestion, actor)
      Success(suggestion)
    end

    private

    def persist(suggestion)
      ActiveRecord::Base.transaction do
        suggestion.update!(state: "accepted")
        suggestion.item&.update!(review_state: "confirmed")
      end
      Success(suggestion)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(suggestion, actor)
      Rails.event.notify(
        "recognition_suggestion.kept", suggestion_id: suggestion.id,
                                       item_id: suggestion.item_id, move_id: suggestion.move_id, actor_id: actor&.id
      )
      Success()
    end
  end
end
