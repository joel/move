# frozen_string_literal: true

require "rails_helper"

# Regression coverage for issue #32: a session cookie that references an
# account which no longer exists (e.g. after a local DB reset, or an account
# deleted server-side) must be treated as logged out. Otherwise Rodauth
# clears it mid-request inside load_memory and wipes in-flight flow state
# (such as the verify-account key), bouncing the user to /login.
RSpec.describe "Stale session for a deleted account" do
  def session_holds?(id)
    session.to_hash.value?(id)
  end

  it "drops an orphaned session and reports the user as logged out" do
    user = create(:user)
    get "/test/login", params: { user_id: user.id }
    expect(response).to have_http_status(:ok)
    expect(session_holds?(user.id)).to be(true)

    user.destroy!

    # Any request carrying the now-orphaned session.
    get account_url

    # current_user resolves to nil, and the dead session_key is gone — the
    # guard cleared it instead of leaving it to derail a later flow.
    expect(response).to have_http_status(:unauthorized)
    expect(session_holds?(user.id)).to be(false)
  end

  it "leaves a valid session intact" do
    user = create(:user)
    Terms::Accept.new.call(user:) # past the #369 gate — probing session auth, not the gate
    get "/test/login", params: { user_id: user.id }

    get account_url

    expect(response).to have_http_status(:success)
    expect(session_holds?(user.id)).to be(true)
  end
end
