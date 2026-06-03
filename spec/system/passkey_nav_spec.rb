# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkey navigation" do
  it "offers an Add passkey link to a signed-in account without a passkey" do
    sign_up_and_login
    visit "/account"

    expect(page).to have_link("Add passkey")

    click_on "Add passkey"

    # Lands on the Rodauth WebAuthn setup page (the registration form).
    expect(page).to have_current_path("/webauthn-setup", ignore_query: true)
    expect(page).to have_button("Setup WebAuthn Authentication")
  end

  it "hides passkey management from signed-out visitors" do
    visit "/"

    expect(page).to have_link("Sign in")
    expect(page).to have_no_link("Add passkey")
    expect(page).to have_no_link("Manage passkeys")
  end
end
