# frozen_string_literal: true

# Resolves the current Organization from the request subdomain.
#
# The apex host (`move.workeverywhere.docker`) has no Organization — it serves
# auth + onboarding. Org subdomains (`<slug>.move.workeverywhere.docker`) resolve
# `Current.organization`; an unknown subdomain is a non-disclosing 404.
module Tenancy
  extend ActiveSupport::Concern

  included do
    before_action :resolve_tenant
    helper_method :current_organization, :tenant_request?
  end

  private

  def app_host
    Rails.configuration.x.app_host
  end

  # The org slug from the subdomain, or nil on the apex host.
  def tenant_slug
    host = request.host.to_s.downcase
    return nil if host == app_host

    suffix = ".#{app_host}"
    return nil unless host.end_with?(suffix)

    label = host.delete_suffix(suffix)
    return nil if label.blank? || label.include?(".")

    label
  end

  def tenant_request?
    tenant_slug.present?
  end

  def current_organization
    Current.organization
  end

  # Populates Current.organization / Current.organization_membership. An unknown
  # subdomain raises RecordNotFound (non-disclosing — never reveals whether an
  # org exists), rendered as a branded 404 by ApplicationController.
  def resolve_tenant
    slug = tenant_slug
    return if slug.nil?

    organization = Organization.find_by(slug: slug)
    raise ActiveRecord::RecordNotFound if organization.nil?

    Current.organization = organization
    Current.organization_membership =
      current_user && organization.organization_memberships.find_by(user: current_user)
  end

  # For org-scoped controllers: require an authenticated member. Non-members get
  # a non-disclosing 404; anonymous users are sent to the apex login.
  def require_organization_membership!
    raise ActiveRecord::RecordNotFound if Current.organization.nil?
    return redirect_to(apex_url("/login"), allow_other_host: true) unless current_user

    raise ActiveRecord::RecordNotFound if Current.organization_membership.nil?
  end

  # Build a URL on the apex host (e.g. to bounce subdomain auth to the apex).
  def apex_url(path)
    port = request.optional_port ? ":#{request.optional_port}" : ""
    "#{request.protocol}#{app_host}#{port}#{path}"
  end
end
