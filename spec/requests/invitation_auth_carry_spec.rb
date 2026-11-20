# frozen_string_literal: true

require "rails_helper"

# D14 (#608) — the invite token must survive the passwordless auth flows:
# Rodauth form POSTs drop query params, so every form re-emits it as a hidden
# field, both emailed links re-carry it (cross-device safe), the post-auth
# redirect returns to the apex landing, and an invited signup gets NO stray
# personal Organization.
RSpec.describe "Invitation token carry through auth (D14)" do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin) }
  let(:organization) { Organization.create!(name: "Acme", slug: "acme-test") }
  let!(:invitation) do
    create(:move_invitation,
           organization:, move_id: move.id, email: "newbie@example.com",
           invited_by: admin, token_digest: MoveInvitation.digest(raw_token))
  end

  define_method(:raw_token) { "d14-carry-spec-raw-token" }

  before do
    host! "example.com"
    ActionMailer::Base.deliveries.clear
  end

  def hidden_token_field
    %(<input type="hidden" name="invite_token" value="#{raw_token}">)
  end

  def link_from_last_mail
    ActionMailer::Base.deliveries.last.body.to_s[%r{https?://\S+}]
  end

  it "renders the hidden token field on the auth forms, refusing junk" do
    get "/create-account", params: { email: "newbie@example.com", invite_token: raw_token }
    expect(response.body).to include(hidden_token_field)

    get "/login", params: { email: "newbie@example.com", invite_token: raw_token }
    expect(response.body).to include(hidden_token_field)

    get "/login", params: { invite_token: "<script>alert(1)</script>" }
    expect(response.body).not_to include("invite_token")
  end

  it "carries the token through signup → verify → landing, with no personal org" do
    post "/create-account", params: { email: "newbie@example.com", invite_token: raw_token }
    expect(response).to have_http_status(:redirect)

    verify_link = link_from_last_mail
    expect(verify_link).to include("invite_token=#{raw_token}")

    # Clicking the link verifies + auto-logs-in (this app's verify_account
    # override has no confirmation form): key-stash redirect, then the verified
    # session lands back on the invitation instead of a personal-org handoff.
    verify_path = URI.parse(verify_link).then { |u| "#{u.path}?#{u.query}" }
    get verify_path
    follow_redirect!

    expect(response).to redirect_to("/invitations?token=#{raw_token}")
    user = User.find_by(email: "newbie@example.com")
    expect(user.status).to eq(2) # verified
    # Invited signup: no stray personal Organization was provisioned.
    expect(OrganizationMembership.exists?(user_id: user.id)).to be(false)
  end

  it "self-heals an invited signup that verified but abandoned the accept" do
    # Verify while carrying the invite (no personal org provisioned)…
    post "/create-account", params: { email: "newbie@example.com", invite_token: raw_token }
    verify_path = URI.parse(link_from_last_mail).then { |u| "#{u.path}?#{u.query}" }
    get verify_path
    follow_redirect!
    user = User.find_by(email: "newbie@example.com")
    expect(OrganizationMembership.exists?(user_id: user.id)).to be(false)

    # …then they abandon and later sign in normally (no invite token). Rather
    # than strand them orgless, after_login provisions their personal org.
    post "/email-auth-request", params: { email: "newbie@example.com" }
    # Follow the emailed link like a browser: its GET stashes the key in the
    # session, which the confirm POST reads (Rodauth 2.47+ refuses a key sent as
    # a plain form param on a non-JSON POST — #820).
    auth_path = URI.parse(link_from_last_mail).then { |u| "#{u.path}?#{u.query}" }
    get auth_path
    follow_redirect!
    post "/email-auth"

    expect(OrganizationMembership.exists?(user_id: user.id)).to be(true)
  end

  it "carries the token through the existing-user magic-link journey" do
    create(:user, email: "newbie@example.com", status: 2)

    post "/email-auth-request", params: { email: "newbie@example.com", invite_token: raw_token }
    expect(response).to have_http_status(:redirect)

    auth_link = link_from_last_mail
    expect(auth_link).to include("invite_token=#{raw_token}")

    auth_path = URI.parse(auth_link).then { |u| "#{u.path}?#{u.query}" }
    get auth_path
    follow_redirect! # same clean-URL redirect as verify-account
    expect(response.body).to include(hidden_token_field)

    # The key rides in the session from the GET above (Rodauth 2.47+ ignores a
    # key sent as a plain form param — #820); only the invite token is posted.
    post "/email-auth", params: { invite_token: raw_token }

    expect(response).to redirect_to("/invitations?token=#{raw_token}")
  end

  it "provisions the personal org as usual when the carried invite is stale" do
    invitation.update!(revoked_at: Time.current)

    post "/create-account", params: { email: "newbie@example.com", invite_token: raw_token }
    verify_path = URI.parse(link_from_last_mail).then { |u| "#{u.path}?#{u.query}" }
    get verify_path
    follow_redirect!

    user = User.find_by(email: "newbie@example.com")
    expect(OrganizationMembership.exists?(user_id: user.id)).to be(true)
  end
end
