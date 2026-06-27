# frozen_string_literal: true

require "rails_helper"

RSpec.describe Terms::Accept do
  let(:user) { create(:user) }

  it "records acceptance of the current terms version with request provenance" do
    result = described_class.new.call(user:, ip: "1.2.3.4", user_agent: "RSpec UA")

    expect(result).to be_success
    acceptance = result.value!
    expect(acceptance.user_id).to eq(user.id)
    expect(acceptance.terms_version).to eq(Terms::CURRENT_VERSION)
    expect(acceptance.ip_address).to eq("1.2.3.4")
    expect(acceptance.user_agent).to eq("RSpec UA")
    expect(acceptance.accepted_at).to be_present
  end

  it "is idempotent — re-accepting the same version returns the existing row" do
    first = described_class.new.call(user:).value!

    expect { described_class.new.call(user:) }.not_to change(TermsAcceptance, :count)
    expect(described_class.new.call(user:).value!.id).to eq(first.id)
  end

  it "emits a terms.accepted event" do
    allow(Rails.event).to receive(:notify)

    described_class.new.call(user:)

    expect(Rails.event).to have_received(:notify).with(
      "terms.accepted",
      hash_including(user_id: user.id, terms_version: Terms::CURRENT_VERSION)
    )
  end
end
