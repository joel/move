# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionSuggestions::Keep do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:suggestion) { create(:recognition_suggestion, :with_item, move:) }

  it "accepts the suggestion and confirms its item" do
    result = described_class.new.call(suggestion:, actor:)

    expect(result).to be_success
    expect(suggestion.reload.state).to eq("accepted")
    expect(suggestion.item.review_state).to eq("confirmed")
  end

  it "emits a recognition_suggestion.kept event" do
    allow(Rails.event).to receive(:notify)
    described_class.new.call(suggestion:, actor:)
    expect(Rails.event).to have_received(:notify).with("recognition_suggestion.kept", hash_including(:suggestion_id))
  end
end
