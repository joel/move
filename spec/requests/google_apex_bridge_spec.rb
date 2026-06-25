# frozen_string_literal: true

require "rails_helper"

# The originating org is carried apex-ward so the post-auth handoff targets the
# subdomain the user came from, not their primary org (#346). On a subdomain the
# Google affordance links to <apex>/login?via=google&org=<slug>; on the apex that
# slug is forwarded into the OmniAuth request as a query param, so it survives the
# round-trip to Google and reaches the callback via omniauth.params.
RSpec.describe "Google apex bridge (#346)" do
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_ID").and_return("test-client-id")
    allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_SECRET").and_return("test-secret")
  end

  it "forwards ?org into the OmniAuth request form on the apex" do
    host! "example.com" # the canonical apex host in test
    get "/login?via=google&org=globex"

    expect(response.body).to include('action="/auth/google?org=globex"')
  end

  it "omits org from the OmniAuth request when none is supplied" do
    host! "example.com"
    get "/login?via=google"

    expect(response.body).to include('action="/auth/google"')
    expect(response.body).not_to include("/auth/google?org=")
  end
end
