# frozen_string_literal: true

require "rails_helper"

# Google sign-in is gated on both credentials being present. On the apex it's a
# real OAuth button (+ One Tap); on org subdomains it's a link that routes
# through the apex. With no credentials (the default) nothing Google renders, so
# the app runs cleanly without Google set up.
RSpec.describe "Social Login" do
  context "when GOOGLE_CLIENT_ID is not configured" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_ID").and_return(nil)
    end

    it "does not show any Google affordance on the login page" do
      visit "/login"

      expect(page).to have_text("Sign in")
      expect(page).to have_no_text("Sign in with Google")
      expect(page).to have_no_text("or continue with")
    end
  end

  context "when fully configured but not on the canonical apex host" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_ID").and_return("test-client-id")
      allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_SECRET").and_return("test-secret")
    end

    # Off the apex (default rack_test host "www.example.com" ≠ apex "example.com"),
    # Google can't run in-place (single registered origin/redirect), so the button
    # is a LINK that routes the user to the apex login, which auto-starts OAuth. It
    # must NOT be a same-host POST button (no `/auth/google` form — which would
    # also raise on the unregistered :google provider).
    it "offers Google as a link routing through the apex" do
      visit "/login"

      expect(page).to have_text("or continue with")
      expect(page).to have_link(
        "Sign in with Google",
        href: "https://example.com/login?via=google"
      )
      expect(page).to have_no_css('form[action="/auth/google"]')
    end
  end

  context "when GOOGLE_CLIENT_SECRET is missing" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_ID").and_return("test-client-id")
      allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_SECRET").and_return(nil)
    end

    # id without secret can't complete the OAuth code exchange, so no Google
    # affordance renders (button or link) and the provider isn't registered.
    it "hides Google entirely" do
      visit "/login"

      expect(page).to have_text("Sign in")
      expect(page).to have_no_text("Sign in with Google")
    end
  end
end
