# frozen_string_literal: true

module RecognitionSuggestions
  # Review action "Ignore" / mark false detection (Design Spec C2): the detection
  # wasn't a real item. Marks the suggestion false_positive and removes its Item
  # from the box (presence_state: removed) so it leaves inventory and future
  # search — reversible via the item's Restore (D5). Caller owns tenant + guard.
  class MarkFalsePositive < BaseAction
    def call(suggestion:, actor:)
      yield persist(suggestion)
      yield emit_event(suggestion, actor)
      Success(suggestion)
    end

    private

    def persist(suggestion)
      ActiveRecord::Base.transaction do
        suggestion.update!(state: "false_positive")
        suggestion.item&.update!(presence_state: "removed")
      end
      Success(suggestion)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(suggestion, actor)
      Rails.event.notify(
        "recognition_suggestion.false_positive", suggestion_id: suggestion.id,
                                                 item_id: suggestion.item_id, move_id: suggestion.move_id, actor_id: actor&.id
      )
      Success()
    end
  end
end
