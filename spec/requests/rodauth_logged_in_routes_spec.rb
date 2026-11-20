# frozen_string_literal: true

require "rails_helper"

# #820 — Rodauth 2.47+ raises "account retrieved multiple times during rodauth
# route" when a route loads the account one way (by login, by key) after it was
# already loaded by session in the same request. We do not configure
# `already_logged_in`, so a signed-in user can still reach the login/token
# routes, and several things load the account by session first: the orphaned-
# session guard (RodauthApp), the Current.user before_action (RodauthController,
# via rails_account), and remember-me's load_memory (deadline extension while
# signed in; auto-login from the cookie after the session expired). The
# `account_reload` override in RodauthMain lets a session-loaded account be
# re-resolved by the route — the pre-2.47 behaviour — instead of a 500.
RSpec.describe "Rodauth login/token routes for a signed-in user (#820)" do
  let(:user) { create(:user, email: "signed-in@example.com", status: 2) }

  before { ActionMailer::Base.deliveries.clear }

  def link_from_last_mail
    ActionMailer::Base.deliveries.last.body.to_s[%r{https?://\S+}]
  end

  def email_auth_key_exists?
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql(["SELECT 1 FROM public.user_email_auth_keys WHERE id = ?", user.id])
    ).present?
  end

  def request_and_consume_sign_in_link
    post "/email-auth-request", params: { email: user.email }
    auth_path = URI.parse(link_from_last_mail).then { |u| "#{u.path}?#{u.query}" }
    get auth_path
    follow_redirect!
    post "/email-auth"
  end

  shared_examples "a signed-in user on the login/token routes" do
    it "requests a sign-in link by login without raising" do
      post "/email-auth-request", params: { email: user.email }

      expect(response).to have_http_status(:redirect)
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "consumes a sign-in link by key without raising" do
      request_and_consume_sign_in_link

      # Success, not the "invalid key" bounce: no error flash, and the single-use
      # key row was consumed (login itself hands off and clears this session).
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to be_nil
      expect(email_auth_key_exists?).to be(false)
    end
  end

  context "when signed in by session on the apex" do
    before do
      host! "example.com"
      get "/test/login", params: { user_id: user.id }
    end

    it_behaves_like "a signed-in user on the login/token routes"

    it "still drops a session whose account no longer exists" do
      user.destroy!

      get "/login"

      expect(response).to have_http_status(:ok)
      expect(session[:account_id]).to be_nil
    end
  end

  context "when remembered on an org subdomain" do
    before do
      stub_current_tenant("acme")
      Terms::Accept.new.call(user:)
      token = SessionHandoffs::Mint.new.call(user:, organization_slug: "acme").value!
      get session_handoff_path(token:) # host-only session + _move_remember cookie
    end

    context "with the remember deadline extension due" do
      # load_memory re-loads the account by session to extend the deadline once
      # extend_remember_deadline_period (1h) has elapsed since the last extension.
      before { travel 2.hours }

      it_behaves_like "a signed-in user on the login/token routes"
    end

    context "with the session expired but the remember cookie valid" do
      # load_memory auto-logs in from the cookie (account_from_remember_cookie).
      before { cookies.delete(Rails.application.config.session_options[:key]) }

      it_behaves_like "a signed-in user on the login/token routes"
    end
  end
end
