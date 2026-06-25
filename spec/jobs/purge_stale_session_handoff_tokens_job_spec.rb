# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeStaleSessionHandoffTokensJob do
  let(:user) { create(:user) }

  def token(expires_at:, consumed_at: nil)
    SessionHandoffToken.create!(
      user:, organization_slug: "acme", token_digest: SecureRandom.hex(16),
      expires_at:, consumed_at:
    )
  end

  it "deletes expired and consumed tokens but keeps fresh, unconsumed ones" do
    expired = token(expires_at: 1.minute.ago)
    consumed = token(expires_at: 1.minute.from_now, consumed_at: Time.current)
    fresh = token(expires_at: 1.minute.from_now)

    described_class.new.perform

    expect(SessionHandoffToken.exists?(fresh.id)).to be(true)
    expect(SessionHandoffToken.exists?(expired.id)).to be(false)
    expect(SessionHandoffToken.exists?(consumed.id)).to be(false)
  end
end
