# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionSuggestions::MarkFalsePositive do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:suggestion) { create(:recognition_suggestion, :with_item, move:) }

  it "marks the suggestion false_positive and removes its item from inventory" do
    result = described_class.new.call(suggestion:, actor:)

    expect(result).to be_success
    expect(suggestion.reload.state).to eq("false_positive")
    expect(suggestion.item.presence_state).to eq("removed")
  end
end
