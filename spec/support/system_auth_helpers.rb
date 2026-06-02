# frozen_string_literal: true

require "cgi"
require "securerandom"

module SystemAuthHelpers
  def sign_up_and_login(email: nil)
    email ||= "user-#{SecureRandom.hex(4)}@example.com"
    visit "/create-account"
    fill_in "Email", with: email
    click_on "Create Account"
    expect(page).to have_current_path("/", ignore_query: true)

    login_as(email: email)
  end

  def login_as(user: nil, email: nil)
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
