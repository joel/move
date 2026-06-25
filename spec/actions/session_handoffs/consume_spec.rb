# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionHandoffs::Consume do
  let(:user) { create(:user) }

  # Mint a real token for `user` targeting `slug`, returning [raw, token].
  def mint(slug: "acme")
    raw = SessionHandoffs::Mint.new.call(user:, organization_slug: slug).value!
    [raw, SessionHandoffToken.find_by(token_digest: SessionHandoffToken.digest(raw))]
  end

  it "returns the bound user for a valid, fresh, matching-tenant token" do
    raw, = mint

    result = described_class.new.call(raw_token: raw, organization_slug: "acme")

    expect(result).to be_success
    expect(result.value!).to eq(user)
  end

  it "consumes the token (single-use): a second consume fails" do
    raw, = mint

    expect(described_class.new.call(raw_token: raw, organization_slug: "acme")).to be_success
    second = described_class.new.call(raw_token: raw, organization_slug: "acme")

    expect(second).to eq(Dry::Monads::Failure(:already_used))
  end

  it "marks the row consumed_at on success" do
    raw, token = mint

    described_class.new.call(raw_token: raw, organization_slug: "acme")

    expect(token.reload.consumed_at).to be_present
  end

  it "rejects an unknown / tampered token" do
    result = described_class.new.call(raw_token: "not-a-real-token", organization_slug: "acme")

    expect(result).to eq(Dry::Monads::Failure(:invalid))
  end

  it "rejects a blank token" do
    expect(described_class.new.call(raw_token: "", organization_slug: "acme"))
      .to eq(Dry::Monads::Failure(:invalid))
    expect(described_class.new.call(raw_token: nil, organization_slug: "acme"))
      .to eq(Dry::Monads::Failure(:invalid))
  end

  it "rejects a token presented on the wrong tenant" do
    raw, = mint(slug: "acme")

    result = described_class.new.call(raw_token: raw, organization_slug: "globex")

    expect(result).to eq(Dry::Monads::Failure(:wrong_tenant))
    expect(SessionHandoffToken.sole.consumed_at).to be_nil # not burned on a tenant mismatch
  end

  it "matches the tenant case-insensitively (citext slug)" do
    raw, = mint(slug: "acme")

    expect(described_class.new.call(raw_token: raw, organization_slug: "ACME")).to be_success
  end

  it "rejects an expired token without consuming it" do
    raw, token = mint
    token.update!(expires_at: 1.second.ago)

    result = described_class.new.call(raw_token: raw, organization_slug: "acme")

    expect(result).to eq(Dry::Monads::Failure(:expired))
    expect(token.reload.consumed_at).to be_nil
  end

  it "rejects when the bound user no longer exists" do
    raw, = mint
    user.destroy

    expect(described_class.new.call(raw_token: raw, organization_slug: "acme"))
      .to eq(Dry::Monads::Failure(:invalid))
  end
end
