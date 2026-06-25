# frozen_string_literal: true

require "rails_helper"

RSpec.describe RodauthMailer do
  let(:user) { create(:user, status: 2) }
  let(:acme) { create(:organization, slug: "acme") }

  before do
    create(:organization_membership, organization: acme, user:)
    # tenant_zone is unset in the test env; the apex host is example.com.
    allow(Rails.application.config.x).to receive(:tenant_zone).and_return("example.com")
  end

  # Extract the sign-in link from the rendered text email.
  def link_in(mail)
    mail.body.to_s[%r{https?://\S+/email-auth\S*}]
  end

  describe "#email_auth (#353)" do
    it "points the magic link at the originating subdomain when the account is a member" do
      mail = described_class.email_auth(nil, user.id, "key-123", "acme")

      expect(link_in(mail)).to start_with("https://acme.example.com/email-auth")
    end

    it "keeps the apex host when the link is requested on the apex (no tenant)" do
      mail = described_class.email_auth(nil, user.id, "key-123", "public")

      link = link_in(mail)
      expect(link).to include("//example.com/email-auth")
      expect(link).not_to include("acme.example.com")
    end

    it "keeps the apex host when the account is NOT a member of the (existing) tenant" do
      create(:organization, slug: "globex") # exists, but the user is not a member

      mail = described_class.email_auth(nil, user.id, "key-123", "globex")

      link = link_in(mail)
      expect(link).to include("//example.com/email-auth")
      expect(link).not_to include("globex.")
    end

    it "keeps the apex host when no tenant is given (backwards-compatible)" do
      mail = described_class.email_auth(nil, user.id, "key-123")

      expect(link_in(mail)).to include("//example.com/email-auth")
    end
  end
end
