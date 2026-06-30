# frozen_string_literal: true

# Base for controllers that run inside an Organization tenant schema (an org
# subdomain): requires an authenticated user and a resolved tenant. Tenancy is
# non-disclosing, so a missing tenant is a 404 — never a redirect that reveals
# the surface exists. Subclasses: MovesController (tenant-scoped, no Move) and
# MoveScopedController (everything nested under /moves/:move_id).
class TenantController < ApplicationController
  before_action :require_authenticated_user!
  before_action :require_tenant!
  # The terms-agreement gate (#369) is applied globally in ApplicationController.

  private

  # Tenancy is non-disclosing: a tenant surface only exists on an org subdomain.
  def require_tenant!
    head :not_found unless current_tenant
  end

  # The Organization registry row for the active tenant (a public/excluded model).
  # Drives the Moves-index sample-provisioning state (#432).
  def current_organization
    return @current_organization if defined?(@current_organization)

    @current_organization = current_tenant && Organization.find_by(slug: current_tenant)
  end
end
