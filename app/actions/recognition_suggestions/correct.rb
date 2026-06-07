# frozen_string_literal: true

module RecognitionSuggestions
  # Review action "Correct" (Design Spec C2): the detection is roughly right but
  # needs editing. Marks the suggestion corrected and its Item confirmed, then the
  # controller routes to the C3 item edit (prefilled) where field changes are
  # saved via Items::Update. A suggestion with no materialized item (a conflict)
  # cannot be corrected — keep/ignore it instead. Caller owns tenant + guard.
  class Correct < BaseAction
    def call(suggestion:, actor:)
      yield validate(suggestion)
      yield persist(suggestion)
      yield emit_event(suggestion, actor)
      Success(suggestion)
    end

    private

    def validate(suggestion)
      suggestion.item ? Success() : Failure(:no_item)
    end

    def persist(suggestion)
      ActiveRecord::Base.transaction do
        suggestion.update!(state: "corrected")
        suggestion.item.update!(review_state: "confirmed")
      end
      Success(suggestion)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(suggestion, actor)
      Rails.event.notify(
        "recognition_suggestion.corrected", suggestion_id: suggestion.id,
                                            item_id: suggestion.item_id, move_id: suggestion.move_id, actor_id: actor&.id
      )
      Success()
    end
  end
end
