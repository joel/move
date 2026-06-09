# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveIntegrationTokens::Revoke do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin) }
  let(:token) { create(:move_integration_token, move:, created_by: admin) }

  it "stamps revoked_at and emits an event" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(token:, actor: admin)

    expect(result).to be_success
    expect(token.reload.revoked_at).to be_present
    expect(Rails.event).to have_received(:notify).with(
      "integration_token.revoked",
      hash_including(move_id: move.id, token_id: token.id, actor_id: admin.id)
    )
  end

  it "makes the token fail authentication afterwards" do
    raw = MoveIntegrationToken.generate_raw_token
    live = create(:move_integration_token, move:, token_digest: MoveIntegrationToken.digest(raw))

    described_class.new.call(token: live, actor: admin)

    expect(MoveIntegrationToken.authenticate(raw)).to be_nil
  end

  it "is idempotent: revoking again neither re-stamps nor re-emits" do
    allow(Rails.event).to receive(:notify)
    token.update!(revoked_at: 2.days.ago)
    original = token.revoked_at

    result = described_class.new.call(token:, actor: admin)

    expect(result).to be_success
    expect(token.reload.revoked_at).to be_within(1.second).of(original)
    expect(Rails.event).not_to have_received(:notify)
  end
end
