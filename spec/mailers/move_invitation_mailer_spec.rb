# frozen_string_literal: true

require "rails_helper"

RSpec.describe MoveInvitationMailer do
  let(:admin) { create(:user, name: "Alex Admin") }
  let(:move) { create(:move, created_by: admin, name: "Seattle Relocation") }
  let(:organization) { Organization.create!(name: "Acme", slug: "acme-test") }
  let(:invitation) do
    create(:move_invitation, organization:, move_id: move.id, invited_by: admin,
                             email: "pat@example.com")
  end

  before do
    allow(Apartment::Tenant).to receive(:switch).and_yield
  end

  it "addresses the invitee, names the Move, and links the apex accept URL" do
    mail = described_class.invite(invitation_id: invitation.id, raw_token: "RAW-TOKEN")

    expect(mail.to).to eq(["pat@example.com"])
    expect(mail.subject).to include("Seattle Relocation")
    expect(mail.text_part.body.to_s).to include("/invitations/RAW-TOKEN")
    expect(mail.html_part.body.to_s).to include("/invitations/RAW-TOKEN")
    expect(mail.text_part.body.to_s).to include("Alex Admin")
  end

  it "degrades to organization-name copy when the Move is gone" do
    move.destroy!

    mail = described_class.invite(invitation_id: invitation.id, raw_token: "RAW-TOKEN")

    expect(mail.subject).to include("Acme")
  end
end
