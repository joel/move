# frozen_string_literal: true

require "rails_helper"

# The Google "Sign in with Google" button and One Tap prompt are gated on
# GOOGLE_CLIENT_ID. With no credentials configured (the default), neither must
# render, so the app runs cleanly without Google set up.
RSpec.describe "Social Login" do
  context "when GOOGLE_CLIENT_ID is not configured" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_ID").and_return(nil)
    end

    it "does not show the Google button on the login page" do
      visit "/login"

      expect(page).to have_text("Sign in")
      expect(page).to have_no_button("Sign in with Google")
      expect(page).to have_no_text("or continue with")
    end
  end

  context "when configured but not on the canonical apex host" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_ID").and_return("test-client-id")
    end

    # OAuth/One Tap derive their callback + JS origin from the request host, but
    # only the apex (test: "example.com") is registered with Google. The default
    # rack_test host is "www.example.com" (a non-canonical public host, like
    # www/move in prod), so Google must stay hidden even though it's configured.
    # (If the host did match the apex, the view would render the button and raise
    # on the unregistered :google provider — a loud failure, not a false pass.)
    it "hides the Google button off the apex host" do
      visit "/login"

      expect(page).to have_text("Sign in")
      expect(page).to have_no_button("Sign in with Google")
    end
  end
end
