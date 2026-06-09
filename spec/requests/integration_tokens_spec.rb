# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Integration tokens" do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin) }
  let(:organization) { Organization.create!(name: "Acme", slug: "acme") }

  before do
    stub_current_user(admin)
    stub_current_tenant("acme")
    allow(Apartment::Tenant).to receive(:current).and_return(organization.slug)
  end

  describe "POST /moves/:move_id/integration_tokens" do
    it "creates a token and reveals the raw value exactly once" do
      expect do
        post move_integration_tokens_path(move), params: { integration_token: { name: "Main Assistant" } }
      end.to change(MoveIntegrationToken, :count).by(1)

      expect(response).to have_http_status(:ok)
      raw = MoveIntegrationToken.last
      # The raw token (mcp_…) is shown in this response body…
      expect(response.body).to match(/mcp_[A-Za-z0-9_-]+/)
      # …and is not the stored digest.
      expect(response.body).not_to include(raw.token_digest)
    end

    it "does not reveal the token again on a subsequent settings load" do
      post move_integration_tokens_path(move), params: { integration_token: { name: "Main Assistant" } }

      get move_settings_path(move)

      expect(response.body).not_to match(/mcp_[A-Za-z0-9_-]{20,}/)
    end

    it "is blocked on an archived move (read-only)" do
      move.update!(status: "archived")

      expect do
        post move_integration_tokens_path(move), params: { integration_token: { name: "Late" } }
      end.not_to change(MoveIntegrationToken, :count)

      expect(response).to redirect_to(move_settings_path(move))
    end

    it "forbids a contributor (admin-only)" do
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      expect do
        post move_integration_tokens_path(move), params: { integration_token: { name: "Sneaky" } }
      end.not_to change(MoveIntegrationToken, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /moves/:move_id/integration_tokens/:id" do
    it "revokes the token for an admin" do
      token = create(:move_integration_token, move:, created_by: admin)

      delete move_integration_token_path(move, token)

      expect(response).to redirect_to(move_settings_path(move))
      expect(token.reload.revoked_at).to be_present
    end

    it "forbids a contributor" do
      token = create(:move_integration_token, move:, created_by: admin)
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      delete move_integration_token_path(move, token)

      expect(response).to have_http_status(:forbidden)
      expect(token.reload.revoked_at).to be_nil
    end
  end
end
