# frozen_string_literal: true

require "rails_helper"

# D14 (#608) — the tenant-side invitation management endpoints (admin-only).
RSpec.describe "Invitations (tenant)" do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin) } # creator → admin member
  let(:organization) { Organization.create!(name: "Acme", slug: "acme") }

  before do
    organization # ensure the org exists for Create's tenant lookup
    stub_current_user(admin)
    stub_current_tenant("acme")
    allow(Apartment::Tenant).to receive(:current).and_return("acme")
  end

  describe "POST /moves/:move_id/invitations" do
    it "streams the new invitation into the pending list with a toast and mails it" do
      expect do
        post move_invitations_path(move),
             params: { invitation: { email: "pat@example.com", role: "contributor" } },
             as: :turbo_stream
      end.to change(ActionMailer::Base.deliveries, :size).by(1)

      invitation = MoveInvitation.find_by(move_id: move.id, email: "pat@example.com")
      expect(invitation).to be_pending
      expect(response.body)
        .to include(%(action="replace" target="#{Components::Members::PendingInvitations::ID}"))
        .and include(Components::Members::PendingRow.dom_id(invitation))
        .and include("highlight")
        .and include(I18n.t("invitations.create.sent", email: "pat@example.com"))
    end

    it "names the remedy for a duplicate pending invitation" do
      create(:move_invitation, organization:, move_id: move.id, email: "pat@example.com")

      post move_invitations_path(move),
           params: { invitation: { email: "pat@example.com", role: "viewer" } }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body)
        .to include(ERB::Util.html_escape(I18n.t("invitations.create.already_invited", email: "pat@example.com")))
    end

    it "rejects an email already on the move and a malformed email" do
      member = create(:user, email: "pat@example.com")
      create(:move_membership, move:, user: member, role: "viewer")

      post move_invitations_path(move),
           params: { invitation: { email: "Pat@Example.com", role: "viewer" } }, as: :turbo_stream
      expect(response.body).to include(I18n.t("invitations.create.already_member"))

      post move_invitations_path(move),
           params: { invitation: { email: "nope", role: "viewer" } }, as: :turbo_stream
      expect(response.body).to include(I18n.t("invitations.create.invalid_email"))
    end

    it "refuses an invite to an archived move with a friendly message" do
      move.update!(status: "archived")

      post move_invitations_path(move),
           params: { invitation: { email: "pat@example.com", role: "viewer" } }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("invitations.create.move_archived"))
      expect(MoveInvitation.exists?(email: "pat@example.com")).to be(false)
    end

    it "forbids non-admins (UI and server)" do
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      post move_invitations_path(move),
           params: { invitation: { email: "x@example.com", role: "viewer" } }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "POST /moves/:move_id/invitations/:id/resend" do
    it "rotates the link, re-mails, and re-renders the row in place" do
      invitation = create(:move_invitation, organization:, move_id: move.id)
      old_digest = invitation.token_digest

      expect do
        post resend_move_invitation_path(move, invitation), as: :turbo_stream
      end.to change(ActionMailer::Base.deliveries, :size).by(1)

      expect(invitation.reload.token_digest).not_to eq(old_digest)
      expect(response.body)
        .to include(%(action="replace" target="#{Components::Members::PendingRow.dom_id(invitation)}"))
    end

    it "refuses to resend on an archived move" do
      invitation = create(:move_invitation, organization:, move_id: move.id)
      move.update!(status: "archived")

      expect do
        post resend_move_invitation_path(move, invitation), as: :turbo_stream
      end.not_to change(ActionMailer::Base.deliveries, :size)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("invitations.create.move_archived"))
    end

    it "refreshes the list when the invitation is no longer pending" do
      invitation = create(:move_invitation, :accepted, organization:, move_id: move.id)

      post resend_move_invitation_path(move, invitation), as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body)
        .to include(%(action="replace" target="#{Components::Members::PendingInvitations::ID}"))
    end
  end

  describe "DELETE /moves/:move_id/invitations/:id" do
    it "revokes and streams the row out" do
      invitation = create(:move_invitation, organization:, move_id: move.id)

      delete move_invitation_path(move, invitation), as: :turbo_stream

      expect(invitation.reload).to be_revoked
      expect(response.body)
        .to include(%(action="remove" target="#{Components::Members::PendingRow.dom_id(invitation)}"))
    end

    it "404s an invitation belonging to another move" do
      foreign = create(:move_invitation, organization:)

      delete move_invitation_path(move, foreign), as: :turbo_stream

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload).not_to be_revoked
    end
  end

  describe "GET /moves/:move_id/members (F1 integration)" do
    it "always shows the invite CTA and form, plus pending invitations newest-first" do
      create(:move_invitation, organization:, move_id: move.id, email: "old@example.com",
                               created_at: 2.days.ago)
      create(:move_invitation, organization:, move_id: move.id, email: "new@example.com")

      get move_members_path(move)

      expect(response.body)
        .to include(I18n.t("members.index.invite"))
        .and include(Components::Members::InviteForm::ID)
        .and include(I18n.t("members.pending.title"))
      expect(response.body.index("new@example.com")).to be < response.body.index("old@example.com")
    end

    it "keeps an expired invitation visible (it still blocks a re-invite until revived/revoked)" do
      create(:move_invitation, :expired, organization:, move_id: move.id, email: "late@example.com")

      get move_members_path(move)

      expect(response.body)
        .to include("late@example.com")
        .and include(I18n.t("members.pending.expired"))
    end

    it "renders no pending section when nothing is pending" do
      get move_members_path(move)

      expect(response.body).to include(%(id="#{Components::Members::PendingInvitations::ID}"))
      expect(response.body).not_to include(I18n.t("members.pending.title"))
    end
  end

  describe "rate limiting" do
    # :null_store never counts in test — assert the limiter is WIRED (a proc
    # before-callback), mirroring spec/requests/mcp_rate_limit_spec.rb.
    it "wires a per-admin rate limit" do
      wired = InvitationsController._process_action_callbacks
                                   .any? { |c| c.kind == :before && !c.filter.is_a?(Symbol) }
      expect(wired).to be(true)
    end
  end
end
