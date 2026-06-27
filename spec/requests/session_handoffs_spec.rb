# frozen_string_literal: true

require "rails_helper"

# Apex->subdomain session handoff (#280). The apex mints a single-use token and
# redirects to <slug>.<zone>/session/handoff?token=...; this endpoint, running on
# the org subdomain, exchanges it for the subdomain's OWN host-only session.
#
# SessionHandoffToken lives in the public schema (excluded Apartment model), so
# stubbing current_tenant (as the other request specs do) is enough — no tenant
# schema DDL is needed.
RSpec.describe "GET /session/handoff" do
  let(:user) { create(:user, status: 2) } # 2 = open/verified (passwordless)

  before do
    stub_current_tenant("acme")
    # Past the #369 terms gate: the post-handoff probe (GET /account) is gated, and
    # this spec exercises session auth, not the gate. A real handed-off user has
    # already accepted.
    Terms::Accept.new.call(user:)
  end

  def mint_for(slug = "acme", as: user)
    SessionHandoffs::Mint.new.call(user: as, organization_slug: slug).value!
  end

  context "with a valid token for the current tenant" do
    it "establishes a session and redirects to the subdomain home" do
      token = mint_for

      get session_handoff_path(token: token)

      expect(response).to redirect_to("/")
    end

    it "authenticates subsequent requests (the new host-only session works)" do
      get session_handoff_path(token: mint_for)
      # Follow-up request reuses the cookie jar — proves the real session, not a stub.
      get account_path

      expect(response).to have_http_status(:ok)
    end

    it "re-issues a host-only remember cookie on the subdomain" do
      get session_handoff_path(token: mint_for)

      expect(response.cookies["_move_remember"]).to be_present
    end

    it "consumes the token so it cannot be replayed" do
      token = mint_for

      get session_handoff_path(token: token)
      get account_path # land authenticated once
      reset! # drop cookies — simulate the link being replayed from a fresh client
      stub_current_tenant("acme")
      get session_handoff_path(token: token)

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include("Sign-in link expired")
    end
  end

  context "with an invalid / missing / expired token" do
    it "renders the expired page and does not authenticate, on a bad token" do
      get session_handoff_path(token: "garbage")

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include("Sign-in link expired")
      get account_path
      expect(response).to have_http_status(:unauthorized) # still signed out
    end

    it "renders the expired page when no token is given" do
      get session_handoff_path

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an expired token" do
      token = mint_for
      SessionHandoffToken.sole.update!(expires_at: 1.second.ago)

      get session_handoff_path(token: token)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "when the token's tenant does not match the request" do
    it "rejects a token minted for a different org" do
      token = mint_for("globex")

      get session_handoff_path(token: token) # current tenant is acme

      expect(response).to have_http_status(:unauthorized)
      expect(SessionHandoffToken.sole.consumed_at).to be_nil # not burned on mismatch
    end

    it "rejects the handoff on the apex (no tenant active)" do
      stub_current_tenant(nil)

      get session_handoff_path(token: mint_for)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "when the account is not open" do
    it "refuses to establish a session for a non-open account" do
      closed = create(:user, status: 3) # 3 = closed
      token = mint_for(as: closed)

      get session_handoff_path(token: token)

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
