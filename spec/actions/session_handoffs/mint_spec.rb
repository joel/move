# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionHandoffs::Mint do
  let(:user) { create(:user) }

  it "persists a token bound to the user and tenant, and returns the raw secret" do
    result = described_class.new.call(user:, organization_slug: "acme")

    expect(result).to be_success
    raw = result.value!
    expect(raw).to be_present

    token = SessionHandoffToken.sole
    expect(token.user_id).to eq(user.id)
    expect(token.organization_slug).to eq("acme")
    expect(token.consumed_at).to be_nil
    expect(token.expires_at).to be_within(2.seconds).of(SessionHandoffToken::TTL.from_now)
  end

  it "stores only the digest of the raw token, never the raw value" do
    raw = described_class.new.call(user:, organization_slug: "acme").value!

    token = SessionHandoffToken.sole
    expect(token.token_digest).to eq(SessionHandoffToken.digest(raw))
    expect(token.token_digest).not_to eq(raw)
  end

  it "mints distinct tokens on each call" do
    a = described_class.new.call(user:, organization_slug: "acme").value!
    b = described_class.new.call(user:, organization_slug: "acme").value!

    expect(a).not_to eq(b)
    expect(SessionHandoffToken.count).to eq(2)
  end
end
