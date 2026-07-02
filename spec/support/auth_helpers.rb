# frozen_string_literal: true

module AuthHelpers
  # Stub the signed-in account. A stubbed user is "in the app", which now means
  # they have passed the terms-agreement gate (#369), so record acceptance by
  # default — otherwise every tenant request/controller spec would be redirected
  # to the agreement wall. Pass `accept_terms: false` to exercise the gate itself.
  def stub_current_user(user, accept_terms: true)
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    # A stubbed signed-in user is "in the app": in production you only reach an org
    # subdomain you belong to, so treat them as a member of the current tenant by
    # default — otherwise TenantController#require_membership! would 404 every tenant
    # spec (which sets up MoveMemberships, not OrganizationMemberships). Specs that
    # exercise the membership boundary itself restore the real check with
    # `and_call_original` + real OrganizationMemberships. Mirrors the terms
    # auto-accept above.
    allow_any_instance_of(ApplicationController).to receive(:member_of_current_tenant?).and_return(true)
    Terms::Accept.new.call(user:) if accept_terms && user&.persisted?
  end

  def stub_current_tenant(slug)
    allow_any_instance_of(ApplicationController).to receive(:current_tenant).and_return(slug)
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :controller
  config.include AuthHelpers, type: :request
  config.include AuthHelpers, type: :system
end
