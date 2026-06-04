# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkey navigation" do
  # Rodauth owns user_webauthn_keys directly (no AR model). Insert a row so
  # rodauth.webauthn_setup? reports the account has a registered passkey.
  def seed_passkey(user, webauthn_id: SecureRandom.uuid)
    sql = ActiveRecord::Base.sanitize_sql_array(
      ["INSERT INTO user_webauthn_keys (user_id, webauthn_id, public_key, sign_count, last_use) " \
       "VALUES (?, ?, ?, ?, ?)",
       user.id, webauthn_id, "stub-public-key", 0, Time.current]
    )
    ActiveRecord::Base.connection.execute(sql)
  end

  it "hides passkey management from signed-out visitors" do
    visit "/"

    expect(page).to have_link("Sign in")
    expect(page).to have_no_link("Add passkey")
    expect(page).to have_no_link("Manage passkeys")
  end

  it "offers Add passkey to a signed-in account without a passkey" do
    login_as(user: create(:user))
    visit "/account"

    expect(page).to have_link("Add passkey")
    expect(page).to have_no_link("Manage passkeys")

    click_on "Add passkey"

    expect(page).to have_current_path("/webauthn-setup", ignore_query: true)
    expect(page).to have_button("Setup WebAuthn Authentication")
  end

  it "offers Manage passkeys to a signed-in account with a passkey" do
    user = create(:user)
    login_as(user: user)
    seed_passkey(user)
    visit "/account"

    expect(page).to have_link("Manage passkeys")
    expect(page).to have_no_link("Add passkey")

    click_on "Manage passkeys"

    expect(page).to have_current_path("/webauthn-remove", ignore_query: true)
  end
end
