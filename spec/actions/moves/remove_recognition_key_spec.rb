# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::RemoveRecognitionKey do
  let(:move) { create(:move, recognition_provider: "openai", openai_api_key: "sk-live") }
  let(:actor) { move.created_by }

  it "clears the provider's stored key and emits an event" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, provider: "openai", actor:)

    expect(result).to be_success
    expect(move.reload.openai_api_key).to be_nil
    expect(Rails.event).to have_received(:notify).with(
      "move.recognition_key_removed",
      hash_including(move_id: move.id, actor_id: actor.id, provider: "openai")
    )
  end

  it "is idempotent when the key is already absent" do
    move.update!(gemini_api_key: nil)

    result = described_class.new.call(move:, provider: "gemini", actor:)

    expect(result).to be_success
    expect(move.reload.gemini_api_key).to be_nil
  end

  it "rejects fake / unknown providers (they have no key)" do
    result = described_class.new.call(move:, provider: "fake", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_provider)
  end

  it "refuses to change an archived move" do
    archived = create(:move, :archived, recognition_provider: "openai", openai_api_key: "sk-x")

    result = described_class.new.call(move: archived, provider: "openai")

    expect(result).to be_failure
    expect(result.failure).to eq(:move_archived)
  end
end
