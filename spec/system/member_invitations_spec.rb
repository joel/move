# frozen_string_literal: true

require "rails_helper"

# D14 (#608) — the admin-side invite journey on the Members page. The apex
# accept side is covered end-to-end by request specs (the auth-carry chain);
# rack_test can't hop hosts, so this drives the tenant UI only.
RSpec.describe "Member invitations (F1)" do
  let(:admin) { create(:user, name: "Demo Admin") }
  let(:move) { create(:move, created_by: admin) }

  before do
    Organization.create!(name: "Acme", slug: "acme")
    login_as(user: admin)
    stub_current_tenant("acme")
    allow(Apartment::Tenant).to receive(:current).and_return("acme")
  end

  it "invites an email, shows the pending row, and revokes it" do
    visit move_members_path(move)

    # The CTA is unconditional now — no spare org users exist here.
    expect(page).to have_link(I18n.t("members.index.invite"))

    fill_in I18n.t("members.invite_form.email"), with: "pat@example.com"
    select I18n.t("members.roles.viewer"), from: I18n.t("members.invite_form.role")
    click_button I18n.t("members.invite_form.submit")

    expect(page).to have_text(I18n.t("members.pending.title"))
    expect(page).to have_text("pat@example.com")
    expect(MoveInvitation.find_by(move_id: move.id, email: "pat@example.com")).to be_pending

    click_button I18n.t("members.pending.revoke")

    # The toast still names the email; the pending SECTION is what collapses.
    expect(page).to have_no_text(I18n.t("members.pending.title"))
    expect(MoveInvitation.find_by(move_id: move.id, email: "pat@example.com")).to be_revoked
  end

  it "re-sends a pending invitation with a fresh link" do
    invitation = create(:move_invitation, move_id: move.id, email: "pat@example.com",
                                          organization: Organization.find_by(slug: "acme"))
    old_digest = invitation.token_digest

    visit move_members_path(move)
    click_button I18n.t("members.pending.resend")

    expect(page).to have_text("pat@example.com")
    expect(invitation.reload.token_digest).not_to eq(old_digest)
  end
end
