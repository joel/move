# frozen_string_literal: true

require "rails_helper"

# D14 (#608) — the apex invitation landing + accept. MoveInvitation lives in the
# public schema (excluded Apartment model), so no tenant DDL is needed; the
# accept path's tenant switch is stubbed to yield against the test schema.
RSpec.describe "Invitation acceptance (apex)" do
  let(:admin) { create(:user, name: "Alex Admin") }
  let(:move) { create(:move, created_by: admin, name: "Seattle Relocation") }
  let(:organization) { Organization.create!(name: "Acme", slug: "acme-test") }
  let!(:invitation) do
    create(:move_invitation,
           organization:, move_id: move.id, email: "pat@example.com",
           invited_by: admin, token_digest: MoveInvitation.digest(raw_token))
  end

  define_method(:raw_token) { "d14-request-spec-raw-token" }

  before do
    host! "example.com" # the apex host (action_mailer default_url_options in test)
    allow(Rails.application.config.x).to receive(:tenant_zone).and_return("example.com")
    allow(Apartment::Tenant).to receive(:switch).and_yield
    allow(Apartment::Tenant).to receive(:current).and_return(organization.slug)
  end

  describe "GET /invitations/:token (landing)" do
    it "shows the landing with a create-account CTA for an unknown email" do
      get "/invitations", params: { token: raw_token }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("invitations.show.title")))
      expect(response.body).to include("Seattle Relocation")
      expect(response.body).to include("Alex Admin")
      expect(response.body).to include(I18n.t("invitations.show.create_account"))
      expect(response.body).to include("invite_token=#{raw_token}")
    end

    it "shows a sign-in CTA when the invited email already has an account" do
      create(:user, email: "pat@example.com")

      get "/invitations", params: { token: raw_token }

      expect(response.body).to include(I18n.t("invitations.show.sign_in"))
    end

    it "shows the accept button for the signed-in invited email (case-insensitive)" do
      stub_current_user(create(:user, email: "PAT@example.com"))

      get "/invitations", params: { token: raw_token }

      expect(response.body).to include(I18n.t("invitations.show.accept"))
    end

    it "renders the one generic page for unknown, revoked, expired, and mismatched cases" do
      stub_current_user(create(:user, email: "other@example.com"))
      get "/invitations", params: { token: raw_token }
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("invitations.unavailable.title")))

      stub_current_user(nil)
      get "/invitations", params: { token: "unknown-token" }
      expect(response).to have_http_status(:not_found)

      invitation.update!(revoked_at: Time.current)
      get "/invitations", params: { token: raw_token }
      expect(response).to have_http_status(:not_found)

      invitation.update!(revoked_at: nil, expires_at: 1.minute.ago)
      get "/invitations", params: { token: raw_token }
      expect(response).to have_http_status(:not_found)
    end

    it "keeps the landing available to the matching user after acceptance (resume)" do
      invitee = create(:user, email: "pat@example.com")
      invitation.update!(accepted_at: Time.current)

      get "/invitations", params: { token: raw_token }
      expect(response).to have_http_status(:not_found) # anonymous: consumed = unknown

      stub_current_user(invitee)
      get "/invitations", params: { token: raw_token }
      expect(response).to have_http_status(:ok)
    end

    it "bounces a tenant-host hit to the canonical apex URL" do
      host! "acme-test.example.com"
      stub_current_tenant("acme-test")

      get "/invitations", params: { token: raw_token }

      expect(response).to redirect_to("https://example.com/invitations?token=#{raw_token}")
    end
  end

  describe "POST /invitations/:token (accept)" do
    let(:invitee) { create(:user, email: "pat@example.com") }

    it "joins org then move and hands the session off to the subdomain, landing on the Move" do
      stub_current_user(invitee)

      post "/invitations", params: { token: raw_token }

      expect(response).to have_http_status(:redirect)
      location = response.headers["Location"]
      expect(location).to start_with("https://acme-test.example.com/session/handoff?token=")
      expect(OrganizationMembership.find_by(organization:, user: invitee)&.role).to eq("member")
      expect(move.move_memberships.find_by(user: invitee)&.role).to eq("contributor")

      handoff_raw = location[/token=(.+)\z/, 1]
      token = SessionHandoffToken.find_by(token_digest: SessionHandoffToken.digest(handoff_raw))
      expect(token.return_path).to eq("/moves/#{move.id}/boxes")
    end

    it "re-posting an accepted invite hands off but writes nothing (two tabs / back)" do
      stub_current_user(invitee)
      post "/invitations", params: { token: raw_token }

      expect { post "/invitations", params: { token: raw_token } }
        .not_to change(MoveMembership, :count)
      expect(response).to have_http_status(:redirect)
    end

    it "does not re-add a member removed after they accepted (consumed link)" do
      stub_current_user(invitee)
      post "/invitations", params: { token: raw_token }
      move.move_memberships.find_by(user: invitee).destroy!

      post "/invitations", params: { token: raw_token }

      expect(response).to have_http_status(:redirect) # generic hand-off
      expect(move.move_memberships.exists?(user_id: invitee.id)).to be(false)
    end

    it "renders the generic page for anonymous and mismatched accepts" do
      post "/invitations", params: { token: raw_token }
      expect(response).to have_http_status(:not_found)

      stub_current_user(create(:user, email: "other@example.com"))
      post "/invitations", params: { token: raw_token }
      expect(response).to have_http_status(:not_found)
      expect(OrganizationMembership.where(organization:).count).to eq(0)
    end
  end

  describe "rate limiting" do
    # The test env's :null_store never counts, so assert the limiter is WIRED
    # (a proc before-callback), mirroring spec/requests/mcp_rate_limit_spec.rb.
    it "wires a per-IP rate limit" do
      wired = InvitationAcceptancesController._process_action_callbacks
                                             .any? { |c| c.kind == :before && !c.filter.is_a?(Symbol) }
      expect(wired).to be(true)
    end
  end
end
