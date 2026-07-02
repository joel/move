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
    # A logged-in system-spec user is "in the app": treat them as a member of the
    # current tenant by default so TenantController#require_membership! doesn't 404
    # specs that set a stubbed tenant without an OrganizationMembership. Mirrors
    # stub_current_user in auth_helpers; rack_test runs the app in-process so the
    # stub applies. Specs exercising the boundary itself set up real memberships.
    # rubocop:disable RSpec/AnyInstance -- stubbing a controller predicate, as auth_helpers does
    allow_any_instance_of(ApplicationController).to receive(:member_of_current_tenant?).and_return(true)
    # rubocop:enable RSpec/AnyInstance

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
