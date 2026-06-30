# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemoData::Provision do
  let(:owner) { create(:user) }

  it "provisions a marked sample Move on fake providers, owned by the account" do
    move = described_class.new.call(owner: owner).value!

    expect(move).to be_sample
    expect(move.name).to eq(described_class::SAMPLE_MOVE_NAME)
    expect([move.recognition_provider, move.embedding_provider, move.image_provider]).to all(eq("fake"))
    expect(move.move_memberships.find_by(user: owner)&.role).to eq("admin")
  end

  it "fills the sample with the curated box subset and both item kinds" do
    move = described_class.new.call(owner: owner).value!

    expect(move.boxes.pluck(:number)).to match_array(described_class::SAMPLE_BOX_NUMBERS)
    # Recognition-sourced (from replayed photos) and photo-less manual items.
    expect(move.items.where(created_via: "recognition")).to be_any
    expect(move.items.where(created_via: "manual")).to be_any
  end

  it "is idempotent — a second run never creates a duplicate sample" do
    described_class.new.call(owner: owner)

    expect { described_class.new.call(owner: owner) }.not_to change(Move, :count)
    expect(Move.where(sample: true).count).to eq(1)
  end

  it "builds a search document per item so the sample is searchable immediately" do
    move = described_class.new.call(owner: owner).value!

    expect(ItemSearchDocument.where(move_id: move.id).count).to eq(move.items.count)
  end

  it "rolls back the whole sample if the build fails (no half-built Move persists)" do
    allow(DemoData::SampleBuilder).to receive(:call).and_raise(StandardError, "storage down")

    expect { described_class.new.call(owner: owner) }.to raise_error(StandardError, "storage down")
    expect(Move.where(sample: true)).to be_empty
    expect(Move.count).to eq(0)
  end
end
