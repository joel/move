# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveIntegrationTokens::Create do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin) }
  let(:organization) { Organization.create!(name: "Acme", slug: "acme-test") }

  before do
    # The action resolves the current Organization from the active tenant (the
    # records live in the public test schema; stubbing the reader is enough).
    allow(Apartment::Tenant).to receive(:current).and_return(organization.slug)
  end

  it "mints a token scoped to the Move/Organization and emits an event" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(move:, name: "Main Assistant", actor: admin)
    token = result.value!.token

    aggregate_failures do
      expect(result).to be_success
      expect(token.name).to eq("Main Assistant")
      expect(token.move).to eq(move)
      expect(token.organization_id).to eq(organization.id)
      expect(token.created_by).to eq(admin)
      expect(Rails.event).to have_received(:notify).with(
        "integration_token.created",
        hash_including(move_id: move.id, token_id: token.id, token_name: "Main Assistant", actor_id: admin.id)
      )
    end
  end

  it "returns the raw value once and stores only its digest" do
    minted = described_class.new.call(move:, name: "Main Assistant", actor: admin).value!

    aggregate_failures do
      expect(minted.raw_token).to start_with("mcp_")
      expect(minted.token.token_digest).to eq(MoveIntegrationToken.digest(minted.raw_token))
      # The raw token is not persisted on any column — only its digest is.
      expect(minted.token.attributes.values.map(&:to_s)).not_to include(minted.raw_token)
    end
  end

  it "the minted raw token authenticates back to the same record" do
    result = described_class.new.call(move:, name: "Main Assistant", actor: admin)
    minted = result.value!

    expect(MoveIntegrationToken.authenticate(minted.raw_token)).to eq(minted.token)
  end

  it "rejects a blank name without minting a token" do
    expect do
      result = described_class.new.call(move:, name: "  ", actor: admin)
      expect(result).to be_failure
      expect(result.failure).to eq(:blank_name)
    end.not_to change(MoveIntegrationToken, :count)
  end
end
