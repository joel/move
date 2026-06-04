# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Create account" do
  it "renders the 'email already taken' error without a 500 when the account exists" do
    create(:user, email: "taken@example.com", status: 2) # 2 = verified

    host! "move.workeverywhere.docker"
    post "/create-account", params: { email: "taken@example.com" }

    # The failed create-account re-renders the form; it must not crash on the
    # half-loaded in-flight account (regression: MissingAttributeError roles_mask).
    expect(response).not_to have_http_status(:internal_server_error)
    expect(response.body).not_to include("MissingAttributeError")
  end
end
