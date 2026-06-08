# frozen_string_literal: true

require "rails_helper"

RSpec.describe Qr::Resolve do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  it "resolves a token belonging to the given Move and emits qr.resolved" do
    allow(Rails.event).to receive(:notify)
    box = create(:box, move:, qr_token: "tok-known")

    result = described_class.new.call(move:, token: "tok-known", actor: user)

    expect(result).to be_success
    expect(result.value!).to eq(box)
    expect(Rails.event).to have_received(:notify).with(
      "qr.resolved", hash_including(box_id: box.id, move_id: move.id, actor_id: user.id)
    )
  end

  it "fails non-disclosingly for an unknown token" do
    result = described_class.new.call(move:, token: "does-not-exist", actor: user)

    expect(result).to be_failure
    expect(result.failure).to eq(:unrecognized)
  end

  it "fails non-disclosingly for a blank token" do
    expect(described_class.new.call(move:, token: "", actor: user).failure).to eq(:unrecognized)
  end

  it "does not resolve a token from a different Move (no cross-move disclosure)" do
    other_move = create(:move, created_by: user)
    create(:box, move: other_move, qr_token: "tok-other")

    result = described_class.new.call(move:, token: "tok-other", actor: user)

    expect(result).to be_failure
    expect(result.failure).to eq(:unrecognized)
  end

  it "resolves a box on an archived Move read-only, without mutating status" do
    archived = create(:move, :archived, created_by: user)
    box = create(:box, move: archived, qr_token: "tok-archived", status: "sealed")

    result = described_class.new.call(move: archived, token: "tok-archived", actor: user)

    expect(result).to be_success
    expect(result.value!).to eq(box)
    expect(box.reload.status).to eq("sealed")
  end
end
