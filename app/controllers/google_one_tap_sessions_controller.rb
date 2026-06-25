# frozen_string_literal: true

# Handles the Google "One Tap" credential posted by the
# google-one-tap Stimulus controller. Active only when GOOGLE_CLIENT_ID
# is configured; otherwise the One Tap prompt never renders.
class GoogleOneTapSessionsController < ApplicationController
  # CSRF protection stays ON: #create writes the login session, so an
  # unprotected cross-site POST carrying any valid Move-audience Google ID token
  # could log a victim into the token owner's account (login CSRF). The Stimulus
  # client sends the Rails CSRF token in the X-CSRF-Token header (same-origin
  # fetch, so the session cookie rides along), so legitimate One Tap still works.

  def create
    payload = verify_google_token(params[:credential])
    unless payload
      return render json: { error: "invalid_token" },
                    status: :unprocessable_content
    end

    google_uid = payload["sub"]
    email = payload["email"]&.downcase

    user = find_user_by_identity(google_uid) ||
           find_and_link_user(email, google_uid)

    return login_and_respond(user, payload) if user

    # No matching account. One Tap is login-only; bridge new users into the
    # account-creating OAuth flow (see #signup_redirect).
    render json: {
      error: "no_account",
      redirect: signup_redirect
    }, status: :unprocessable_content
  end

  private

  # One Tap deliberately never creates accounts (it trusts only a tokeninfo
  # lookup, not the full OAuth code exchange). Send a new user into the trusted
  # account-creating path instead: the apex /login?via=google page auto-submits
  # the "Sign in with Google" button to /auth/google, whose OmniAuth callback
  # creates the account (omniauth_create_account?) and lands them on their org
  # subdomain. That bridge only exists when full OAuth creds are configured;
  # otherwise fall back to the self-service signup form.
  def signup_redirect
    return rodauth.create_account_path unless google_credentials_present?

    "#{rodauth.login_path}?via=google"
  end

  def verify_google_token(token)
    return nil if token.blank?

    uri = URI(
      "https://oauth2.googleapis.com/tokeninfo?id_token=#{token}"
    )
    response = Net::HTTP.get_response(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    return nil unless data["aud"] == ENV["GOOGLE_CLIENT_ID"]
    return nil unless data["email_verified"] == "true"

    data
  rescue JSON::ParserError, SocketError, Timeout::Error
    nil
  end

  # Schema-qualify the omniauth identities table to `public`: it has no AR
  # model, so Apartment clones it (empty) into each tenant schema, and the
  # tenant search_path is active on org subdomains. Without `public.` this
  # raw SQL would read/write the wrong (empty) tenant copy.
  def find_user_by_identity(google_uid)
    sql = ActiveRecord::Base.sanitize_sql_array(
      [
        "SELECT user_id FROM public.user_omniauth_identities " \
        "WHERE provider = 'google' AND uid = ?",
        google_uid
      ]
    )
    row = ActiveRecord::Base.connection.select_one(sql)
    User.find(row["user_id"]) if row
  end

  def find_and_link_user(email, google_uid)
    user = User.find_by(email: email)
    return unless user

    sql = ActiveRecord::Base.sanitize_sql_array(
      [
        "INSERT INTO public.user_omniauth_identities " \
        "(id, user_id, provider, uid) VALUES (?, ?, ?, ?)",
        SecureRandom.uuid, user.id, "google", google_uid
      ]
    )
    ActiveRecord::Base.connection.execute(sql)
    user
  end

  def login_and_respond(user, payload)
    open_status = rodauth.account_open_status_value

    if user.status != open_status
      # Auto-verify unverified accounts (Google verified the email).
      # Mirrors omniauth_verify_account? true in rodauth_main.rb.
      # Unverified (1) < open (2) < closed (3) — only promote upward.
      unless user.status < open_status
        return render json: { error: "account_not_active" },
                      status: :unprocessable_content
      end
      user.update!(status: open_status)
    end

    rodauth.account_from_id(user.id)
    session[rodauth.session_key] = user.id
    session[rodauth.authenticated_by_session_key] = ["google_one_tap"]
    rodauth.remember_login

    # Provision a personal Organization if the linked account somehow has none
    # (idempotent), then land on the user's org home rather than the apex.
    rodauth.ensure_personal_organization
    backfill_name(user, payload)

    render json: { ok: true, redirect: org_home_redirect }
  end

  def org_home_redirect
    org = rodauth.primary_organization
    # Host-only cookies (#280): hand the session to the subdomain via a single-use
    # token rather than relying on the apex session cookie traveling there.
    org ? rodauth.tenant_handoff_url(org.slug) : "/"
  end

  def backfill_name(user, payload)
    return if user.name.present?

    name = payload["name"]
    user.update!(name: name) if name.present?
  end
end
