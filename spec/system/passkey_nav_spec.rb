# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkey navigation" do
  # Rodauth owns user_webauthn_keys directly (no AR model). Insert a row so
  # rodauth.webauthn_setup? reports the account has a registered passkey.
  # Auth tables live in the public schema (no AR model), so qualify explicitly —
  # otherwise on an org subdomain Apartment's search_path reads the tenant copy.
  def seed_passkey(user, webauthn_id: SecureRandom.uuid, name: nil)
    sql = ActiveRecord::Base.sanitize_sql_array(
      ["INSERT INTO public.user_webauthn_keys " \
       "(user_id, webauthn_id, public_key, sign_count, last_use, name) " \
       "VALUES (?, ?, ?, ?, ?, ?)",
       user.id, webauthn_id, "stub-public-key", 0, Time.current, name]
    )
    ActiveRecord::Base.connection.execute(sql)
  end

  def passkey_count(user)
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array(
        ["SELECT count(*) FROM public.user_webauthn_keys WHERE user_id = ?", user.id]
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

    expect(page).to have_current_path("/account/passkeys/new", ignore_query: true)
    expect(page).to have_button("Add passkey") # passkey wording, not WebAuthn jargon
  end

  it "lets an account with a passkey add another (no excludeCredentials block)" do
    user = create(:user)
    login_as(user: user)
    seed_passkey(user, webauthn_id: "existing-key", name: "Phone")

    visit "/account/passkeys/new"

    # The credential options must exclude nothing, so a synced/duplicate
    # authenticator can still register another passkey (no InvalidStateError).
    opts = find_by_id("webauthn-setup-form")["data-credential-options"]
    expect(JSON.parse(opts).fetch("excludeCredentials")).to eq([])
    expect(page).to have_no_text(/WebAuthn|authenticator/i)
  end

  it "offers Manage passkeys to a signed-in account with a passkey" do
    user = create(:user)
    login_as(user: user)
    seed_passkey(user)
    visit "/account"

    expect(page).to have_link("Manage passkeys")
    expect(page).to have_no_link("Add passkey")

    click_on "Manage passkeys"

    expect(page).to have_current_path("/account/passkeys", ignore_query: true)
  end

  it "lists each passkey by name and removes one without an explicit selection" do
    user = create(:user)
    login_as(user: user)
    seed_passkey(user, webauthn_id: "key-phone", name: "Pixel phone")
    seed_passkey(user, webauthn_id: "key-laptop", name: "Work laptop")

    visit "/account/passkeys"

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

  it "lands on the account page after removing the last passkey" do
    user = create(:user)
    login_as(user: user)
    seed_passkey(user, webauthn_id: "only-key", name: "Only key")

    visit "/account/passkeys"
    click_on "Remove passkey"

    # No passkeys remain → the manage page would bounce to the generic 2FA flow,
    # so we send the user to the account page (Security card offers "Add passkey").
    expect(page).to have_current_path("/account", ignore_query: true)
    expect(passkey_count(user)).to eq(0)
  end

  it "badges the current device's passkey and hides Add on that device" do
    user = create(:user)
    login_as(user: user)
    seed_passkey(user, webauthn_id: "key-phone", name: "Pixel phone")
    seed_passkey(user, webauthn_id: "key-laptop", name: "Work laptop")
    # Pretend this session signed in with the phone passkey.
    allow_any_instance_of(RodauthMain) # rubocop:disable RSpec/AnyInstance
      .to receive(:authenticated_webauthn_id).and_return("key-phone")

    visit "/account/passkeys"

    # Exactly one row (the signed-in credential) is badged + highlighted.
    expect(page).to have_text("This device", count: 1)
    phone = find("label[data-webauthn-id='key-phone']")
    laptop = find("label[data-webauthn-id='key-laptop']")
    expect(phone[:class]).to include("ring-2")
    expect(phone).to have_text("This device")
    expect(laptop).to have_no_text("This device")
    expect(laptop[:class]).not_to include("ring-2")
    # This device already has a passkey → no "Add another" card.
    expect(page).to have_no_text("Add another passkey")
  end

  # Regression for the schema-qualification bug: on an org subdomain Apartment
  # points search_path at the tenant schema, so an unqualified user_webauthn_keys
  # query reads the empty tenant copy and lists no keys (removal then always
  # fails). This provisions a real tenant + subdomain host to exercise that path.
  describe "on an organization subdomain" do
    let(:slug) { "jspk" }
    let(:org_user) { create(:user) }
    let(:host) { "#{slug}.lvh.me" }

    around do |example|
      original_zone = Rails.application.config.x.tenant_zone
      original_app_host = Capybara.app_host
      original_include_port = Capybara.always_include_port

      Rails.application.config.x.tenant_zone = "lvh.me"
      Capybara.app_host = "http://#{host}"
      Capybara.always_include_port = true

      Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
      Organizations::Create.new.call(name: "JS Passkey Org", slug: slug, owner: org_user).value!

      example.run
    ensure
      Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
      Rails.application.config.x.tenant_zone = original_zone
      Capybara.app_host = original_app_host
      Capybara.always_include_port = original_include_port
    end

    it "lists and removes public-schema passkeys (not the empty tenant copy)" do
      seed_passkey(org_user, webauthn_id: "pk-tenant", name: "Phone")
      login_as(user: org_user)

      visit "/account/passkeys"

      expect(page).to have_text("Phone")
      expect(page).to have_selector(:radio_button, count: 1)

      click_on "Remove passkey"

      expect(page).to have_no_text("must select")
      expect(passkey_count(org_user)).to eq(0)
    end
  end
end
