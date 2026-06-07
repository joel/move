# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionSuggestions::Correct do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:suggestion) { create(:recognition_suggestion, :with_item, move:) }

  it "marks the suggestion corrected and confirms its item" do
    result = described_class.new.call(suggestion:, actor:)

    expect(result).to be_success
    expect(suggestion.reload.state).to eq("corrected")
    expect(suggestion.item.review_state).to eq("confirmed")
  end

  it "fails when the suggestion has no materialized item (e.g. a conflict)" do
    conflict = create(:recognition_suggestion, :conflict, move:)
    result = described_class.new.call(suggestion: conflict, actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:no_item)
  end
end
