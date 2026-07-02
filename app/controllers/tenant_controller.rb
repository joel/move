# frozen_string_literal: true

# Base for controllers that run inside an Organization tenant schema (an org
# subdomain): requires an authenticated user and a resolved tenant. Tenancy is
# non-disclosing, so a missing tenant is a 404 — never a redirect that reveals
# the surface exists. Subclasses: MovesController (tenant-scoped, no Move) and
# MoveScopedController (everything nested under /moves/:move_id).
class TenantController < ApplicationController
  # require_membership! is PREPENDED so it runs BEFORE the inherited terms gate
  # (ApplicationController#require_terms_agreement!): an authenticated non-member of
  # the current Organization gets a non-disclosing 404 on every tenant surface
  # uniformly — never a terms redirect that would reveal the subdomain resolves to a
  # real tenant (or store the foreign path as terms_return_to). The terms gate is
  # left untouched on non-tenant controllers (e.g. AccountsController), which still
  # block unaccepted accounts there.
  prepend_before_action :require_membership!
  before_action :require_authenticated_user!
  before_action :require_tenant!

  private

  # Tenancy is non-disclosing: a tenant surface only exists on an org subdomain.
  def require_tenant!
    head :not_found unless current_tenant
  end

  # Authorize at the tenant boundary: the user must belong to the current
  # Organization. Isolation must be *enforced* here, not assumed from "you could
  # only get a session on a subdomain you belong to" — so a session that reaches a
  # foreign subdomain cannot act on it (e.g. create a Move and self-assign admin).
  # Non-disclosing 404 to match the tenancy posture (never reveal the org exists).
  # Unauthenticated requests fall through to require_authenticated_user! (the
  # login/unauthorized response) instead of being 404'd here.
  def require_membership!
    return if current_user.nil?

    head :not_found unless member_of_current_tenant?
  end

  # The Organization registry row for the active tenant (a public/excluded model).
  # Drives the Moves-index sample-provisioning state (#432).
  def current_organization
    return @current_organization if defined?(@current_organization)

    @current_organization = current_tenant && Organization.find_by(slug: current_tenant)
  end
end
