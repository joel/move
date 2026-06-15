# frozen_string_literal: true

require "rails_helper"

RSpec.describe Moves::SetRecognitionProvider do
  let(:move) { create(:move, recognition_provider: "fake") }
  let(:actor) { move.created_by }

  it "sets the provider and stores the submitted key, emitting an event without the key" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, provider: "openai", api_key: "sk-live", actor:)

    expect(result).to be_success
    move.reload
    expect(move.recognition_provider).to eq("openai")
    expect(move.openai_api_key).to eq("sk-live")
    expect(Rails.event).to have_received(:notify).with(
      "move.recognition_provider_changed",
      hash_including(move_id: move.id, actor_id: actor.id, provider: "openai")
    )
    # The key value is never part of the event payload.
    expect(Rails.event).not_to have_received(:notify).with(anything, hash_including(api_key: anything))
  end

  it "switches to fake without requiring a key" do
    move.update!(recognition_provider: "openai", openai_api_key: "sk-old")

    result = described_class.new.call(move:, provider: "fake", actor:)

    expect(result).to be_success
    expect(move.reload.recognition_provider).to eq("fake")
  end

  it "fails closed when a real provider is selected with no key (new or stored)" do
    result = described_class.new.call(move:, provider: "anthropic", api_key: "", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:api_key_required)
    expect(move.reload.recognition_provider).to eq("fake")
  end

  it "allows switching to a real provider that already has a stored key" do
    move.update!(gemini_api_key: "g-stored")

    result = described_class.new.call(move:, provider: "gemini", api_key: "", actor:)

    expect(result).to be_success
    expect(move.reload.recognition_provider).to eq("gemini")
    expect(move.gemini_api_key).to eq("g-stored")
  end

  it "leaves an existing key untouched when the submitted key is blank" do
    move.update!(recognition_provider: "openai", openai_api_key: "sk-keep")

    described_class.new.call(move:, provider: "openai", api_key: "  ", actor:)

    expect(move.reload.openai_api_key).to eq("sk-keep")
  end

  it "rejects an unknown provider" do
    result = described_class.new.call(move:, provider: "skynet", actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:invalid_provider)
  end

  it "refuses to change an archived (read-only) move" do
    archived = create(:move, :archived)

    result = described_class.new.call(move: archived, provider: "fake")

    expect(result).to be_failure
    expect(result.failure).to eq(:move_archived)
  end
end
