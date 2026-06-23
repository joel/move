# frozen_string_literal: true

require "rails_helper"

# Google One Tap (FedCM) credential endpoint. The Stimulus controller POSTs a
# Google ID token here; the controller verifies it server-side, finds/links the
# account, logs it in, and provisions a personal Organization if needed.
#
# Apartment::Tenant.create is stubbed throughout so org provisioning exercises
# the registry rows (Organization + membership) without running schema DDL.
RSpec.describe "POST /auth/google/one_tap" do
  let(:user) { create(:user, email: "jane@example.com", name: nil) }
  let(:google_uid) { "google-uid-#{SecureRandom.hex(4)}" }
  let(:google_payload) do
    {
      "sub" => google_uid,
      "email" => user.email,
      "email_verified" => "true",
      "name" => "Jane Doe",
      "aud" => "test-google-client-id"
    }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_ID")
                              .and_return("test-google-client-id")
    allow(Apartment::Tenant).to receive(:create)

    stub_google_tokeninfo(google_payload)
  end

  context "with existing OmniAuth identity" do
    before { insert_identity(user, google_uid) }

    it "logs in the user" do
      post "/auth/google/one_tap",
           params: { credential: "valid-jwt" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("ok" => true)
    end

    it "sets a remember cookie for persistent sessions" do
      post "/auth/google/one_tap",
           params: { credential: "valid-jwt" }, as: :json

      expect(response.cookies["_remember"]).to be_present
    end
  end

  context "with matching email but no identity" do
    it "creates the identity and logs in" do
      expect do
        post "/auth/google/one_tap",
             params: { credential: "valid-jwt" }, as: :json
      end.to change { identity_count(google_uid) }.from(0).to(1)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("ok" => true)
    end
  end

  context "when the linked account has no Organization" do
    before { insert_identity(user, google_uid) }

    it "provisions a personal Organization and redirects to its home" do
      expect do
        post "/auth/google/one_tap",
             params: { credential: "valid-jwt" }, as: :json
      end.to change { OrganizationMembership.where(user_id: user.id).count }
        .from(0).to(1)

      expect(response).to have_http_status(:ok)
      slug = Organization.joins(:organization_memberships)
                         .find_by(organization_memberships: { user_id: user.id })
                         .slug
      expect(response.parsed_body["redirect"]).to include(slug)
    end
  end

  context "with no matching account (OAuth redirect flow unavailable)" do
    before do
      stub_google_tokeninfo(google_payload.merge("email" => "unknown@example.com"))
    end

    # Only GOOGLE_CLIENT_ID is configured here (no secret), so the account-
    # creating OAuth button isn't available — fall back to self-service signup.
    it "returns no_account error pointing at self-service signup" do
      post "/auth/google/one_tap",
           params: { credential: "valid-jwt" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      body = response.parsed_body
      expect(body["error"]).to eq("no_account")
      expect(body["redirect"]).to eq("/create-account")
    end
  end

  context "with no matching account and full Google OAuth configured" do
    before do
      allow(ENV).to receive(:[]).with("GOOGLE_CLIENT_SECRET")
                                .and_return("test-google-client-secret")
      stub_google_tokeninfo(google_payload.merge("email" => "unknown@example.com"))
    end

    # One Tap is login-only; a new user is bridged into the account-creating
    # OAuth flow (apex /login?via=google auto-submits to /auth/google).
    it "bridges new users into the account-creating OAuth flow" do
      post "/auth/google/one_tap",
           params: { credential: "valid-jwt" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      body = response.parsed_body
      expect(body["error"]).to eq("no_account")
      expect(body["redirect"]).to eq("/login?via=google")
    end
  end

  context "with a closed account" do
    before do
      user.update!(status: 3) # closed
      insert_identity(user, google_uid)
    end

    it "returns account_not_active error" do
      post "/auth/google/one_tap",
           params: { credential: "valid-jwt" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("account_not_active")
    end
  end

  context "with an unverified account" do
    before { insert_identity(user, google_uid) }

    it "auto-verifies (promotes status to open) and logs in" do
      user.update!(status: 1) # unverified

      post "/auth/google/one_tap",
           params: { credential: "valid-jwt" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.status).to eq(2) # open
    end
  end

  context "with invalid token" do
    before do
      mock_response = instance_double(Net::HTTPBadRequest)
      allow(mock_response).to receive(:is_a?)
        .with(Net::HTTPSuccess).and_return(false)
      allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
    end

    it "returns invalid_token error" do
      post "/auth/google/one_tap",
           params: { credential: "bad-jwt" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("invalid_token")
    end
  end

  context "with missing credential" do
    it "returns invalid_token error" do
      post "/auth/google/one_tap", as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("invalid_token")
    end
  end

  context "with wrong audience" do
    before do
      stub_google_tokeninfo(google_payload.merge("aud" => "wrong-client-id"))
    end

    it "returns invalid_token error" do
      post "/auth/google/one_tap",
           params: { credential: "valid-jwt" }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("invalid_token")
    end
  end

  context "with CSRF protection enabled (production-like)" do
    around do |example|
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    before { insert_identity(user, google_uid) }

    # #create writes the login session, so a cross-site POST without the CSRF
    # token (carrying any valid Move-audience token) must be rejected before it
    # can log the visitor in. The Stimulus client sends X-CSRF-Token, so genuine
    # same-origin One Tap is unaffected.
    it "rejects a POST that lacks the CSRF token" do
      post "/auth/google/one_tap",
           params: { credential: "valid-jwt" }, as: :json

      expect(response).not_to have_http_status(:ok)
      expect(response.parsed_body).not_to include("ok" => true)
    end
  end

  context "with name backfill" do
    before { insert_identity(user, google_uid) }

    it "sets the user name from the Google profile when blank" do
      post "/auth/google/one_tap",
           params: { credential: "valid-jwt" }, as: :json

      expect(user.reload.name).to eq("Jane Doe")
    end

    it "does not overwrite an existing name" do
      user.update!(name: "Existing Name")

      post "/auth/google/one_tap",
           params: { credential: "valid-jwt" }, as: :json

      expect(user.reload.name).to eq("Existing Name")
    end
  end

  # Stub Google's tokeninfo endpoint (the controller GETs it via Net::HTTP).
  def stub_google_tokeninfo(payload)
    mock_response = instance_double(Net::HTTPOK, body: payload.to_json)
    allow(mock_response).to receive(:is_a?)
      .with(Net::HTTPSuccess).and_return(true)
    allow(Net::HTTP).to receive(:get_response).and_return(mock_response)
  end

  # Schema-qualify to public to mirror the hardened controller (the table has no
  # AR model and is cloned empty into tenant schemas).
  def insert_identity(user, uid)
    sql = ActiveRecord::Base.sanitize_sql_array(
      [
        "INSERT INTO public.user_omniauth_identities " \
        "(id, user_id, provider, uid) VALUES (?, ?, ?, ?)",
        SecureRandom.uuid, user.id, "google", uid
      ]
    )
    ActiveRecord::Base.connection.execute(sql)
  end

  def identity_count(uid)
    sql = ActiveRecord::Base.sanitize_sql_array(
      [
        "SELECT COUNT(*) FROM public.user_omniauth_identities " \
        "WHERE provider = 'google' AND uid = ?", uid
      ]
    )
    ActiveRecord::Base.connection.select_value(sql)
  end
end
