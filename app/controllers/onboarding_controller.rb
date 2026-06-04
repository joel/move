# frozen_string_literal: true

# Post-signup onboarding: create the first Organization. The creator becomes its
# account admin, then is redirected to the new org subdomain.
class OnboardingController < ApplicationController
  before_action :require_authenticated_user!

  # GET /onboarding/new
  def new
    @organization = Organization.new
    render Views::Onboarding::New.new(organization: @organization)
  end

  # POST /onboarding
  def create
    @organization = Organization.new(organization_params.merge(created_by_user: current_user))

    if create_organization
      redirect_to organization_root_url(@organization),
                  allow_other_host: true, notice: t(".created")
    else
      render Views::Onboarding::New.new(organization: @organization),
             status: :unprocessable_content
    end
  end

  private

  def create_organization
    Organization.transaction do
      @organization.save!
      @organization.organization_memberships.create!(user: current_user, account_admin: true)
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def organization_params
    params.expect(organization: %i[name slug])
  end

  # Root URL on the new Organization's subdomain.
  def organization_root_url(organization)
    port = request.optional_port ? ":#{request.optional_port}" : ""
    TenantHost.org_root_url(organization.slug, protocol: request.protocol, port:)
  end
end
