# frozen_string_literal: true

require "rails_helper"

# The terms-agreement gate (#369): every account must accept the current terms
# version before any tenant surface. `moves_path` (MovesController < TenantController)
# stands in for "any gated app surface".
RSpec.describe "Terms agreement gate" do
  let(:user) { create(:user) }

  before { stub_current_tenant("acme") }

  describe "the gate on a tenant surface" do
    it "redirects an account that has not accepted to the agreement page" do
      stub_current_user(user, accept_terms: false)

      get moves_path

      expect(response).to redirect_to(agreement_path)
    end

    it "lets an account that has accepted through" do
      stub_current_user(user) # accepts by default

      get moves_path

      expect(response).to have_http_status(:ok)
    end

    it "also gates account management (#369: 'cannot do anything')" do
      stub_current_user(user, accept_terms: false)

      get account_path

      expect(response).to redirect_to(agreement_path)
    end

    it "gates other authenticated non-tenant surfaces too (admin /users)" do
      admin = create(:user, :admin)
      stub_current_user(admin, accept_terms: false)

      get users_path

      expect(response).to redirect_to(agreement_path)
    end

    it "does NOT gate on the apex broker host (no tenant) — avoids a 404 wall" do
      stub_current_user(user, accept_terms: false)
      stub_current_tenant(nil) # apex / non-tenant host

      get account_path

      # The tenant-only wall would 404 here, so the gate stays out of the way.
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /agreement" do
    it "renders the agreement wall for a not-yet-accepted account" do
      stub_current_user(user, accept_terms: false)

      get agreement_path

      expect(response).to have_http_status(:ok)
      # `&` renders HTML-escaped (&amp;), so match an ampersand-free substring.
      expect(response.body).to include("Risk Acknowledgement")
    end

    it "redirects an already-accepted account away from the wall" do
      stub_current_user(user) # accepts by default

      get agreement_path

      expect(response).to redirect_to(moves_path)
    end
  end

  describe "POST /agreement" do
    it "records acceptance and lets the account into the app" do
      stub_current_user(user, accept_terms: false)

      expect do
        post accept_agreement_path
      end.to change { user.terms_acceptances.where(terms_version: Terms::CURRENT_VERSION).count }
        .from(0).to(1)

      expect(response).to redirect_to(moves_path)
    end

    it "is idempotent on a double-submit" do
      stub_current_user(user, accept_terms: false)
      post accept_agreement_path

      expect { post accept_agreement_path }.not_to change(TermsAcceptance, :count)
      expect(response).to redirect_to(moves_path)
    end

    it "returns the user to the deep link they were headed for" do
      stub_current_user(user, accept_terms: false)

      get account_path # a gated deep link — remembers the destination
      expect(response).to redirect_to(agreement_path)

      post accept_agreement_path # same session → consumes the remembered path
      expect(response).to redirect_to(account_path)
    end
  end
end
