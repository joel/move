# frozen_string_literal: true

require "cgi"
require "securerandom"

module SystemAuthHelpers
  def sign_up_and_login(email: nil, accept_terms: true)
    email ||= "user-#{SecureRandom.hex(4)}@example.com"
    visit "/create-account"
    fill_in "Email", with: email
    click_on "Create Account"
    expect(page).to have_current_path("/", ignore_query: true)

    login_as(email:, accept_terms:)
  end

  # Logging in puts the user "in the app", which now means they have passed the
  # terms-agreement gate (#369). Record acceptance by default so existing system
  # specs land in the app instead of the agreement wall; pass `accept_terms:
  # false` to exercise the gate.
  def login_as(user: nil, email: nil, accept_terms: true)
    user ||= User.find_by(email:) if email
    Terms::Accept.new.call(user:) if accept_terms && user&.persisted?

    if user
      visit "/test/login?user_id=#{CGI.escape(user.id.to_s)}"
    else
      visit "/test/login?email=#{CGI.escape(email.to_s)}"
    end
  end
end

RSpec.configure do |config|
  config.include SystemAuthHelpers, type: :system
end
