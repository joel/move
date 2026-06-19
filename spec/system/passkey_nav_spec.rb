# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkey navigation" do
  # Rodauth owns user_webauthn_keys directly (no AR model). Insert a row so
  # rodauth.webauthn_setup? reports the account has a registered passkey.
  def seed_passkey(user, webauthn_id: SecureRandom.uuid, name: nil)
    sql = ActiveRecord::Base.sanitize_sql_array(
      ["INSERT INTO user_webauthn_keys (user_id, webauthn_id, public_key, sign_count, last_use, name) " \
       "VALUES (?, ?, ?, ?, ?, ?)",
       user.id, webauthn_id, "stub-public-key", 0, Time.current, name]
    )
    ActiveRecord::Base.connection.execute(sql)
  end

  def passkey_count(user)
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(
        ["SELECT count(*) FROM user_webauthn_keys WHERE user_id = ?", user.id]
      )
    )
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

  it "lists each passkey by name and removes one without an explicit selection" do
    user = create(:user)
    login_as(user: user)
    seed_passkey(user, webauthn_id: "key-phone", name: "Pixel phone")
    seed_passkey(user, webauthn_id: "key-laptop", name: "Work laptop")

    visit "/webauthn-remove"

    # Each named key is listed individually, and the friendly button copy is used.
    expect(page).to have_text("Pixel phone")
    expect(page).to have_text("Work laptop")
    expect(page).to have_button("Remove passkey")
    # The first key is pre-selected so a submit always carries a valid value.
    expect(page).to have_selector(:radio_button, checked: true, count: 1)

    # Remove without manually choosing — previously this failed with
    # "must select a valid webauthn authenticator to remove".
    click_on "Remove passkey"

    expect(page).to have_no_text("must select")
    expect(passkey_count(user)).to eq(1)
  end
end
