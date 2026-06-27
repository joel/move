# frozen_string_literal: true

require "rails_helper"

RSpec.describe TermsAcceptance do
  let(:user) { create(:user) }

  it "is valid with a user, version and accepted_at" do
    record = described_class.new(user:, terms_version: "2026-06-27", accepted_at: Time.current)
    expect(record).to be_valid
  end

  it "requires terms_version and accepted_at" do
    record = described_class.new(user:)

    expect(record).not_to be_valid
    expect(record.errors[:terms_version]).to be_present
    expect(record.errors[:accepted_at]).to be_present
  end

  it "enforces one acceptance per (user, version) at the database level" do
    described_class.create!(user:, terms_version: "v1", accepted_at: Time.current)

    expect do
      described_class.create!(user:, terms_version: "v1", accepted_at: Time.current)
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows the same user to accept a different version" do
    described_class.create!(user:, terms_version: "v1", accepted_at: Time.current)
    other = described_class.new(user:, terms_version: "v2", accepted_at: Time.current)

    expect(other).to be_valid
  end
end
