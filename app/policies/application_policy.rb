# frozen_string_literal: true

class ApplicationPolicy < ActionPolicy::Base
  authorize :user, allow_nil: true

  private

  def admin?
    user&.role?(:admin)
  end

  # Tenant-aware helpers (Phase D1) — read the Organization resolved from the
  # subdomain. Move-role helpers are added in PR2.
  def current_organization
    Current.organization
  end

  def organization_member?
    Current.organization_membership.present?
  end

  def account_admin?
    Current.organization_membership&.account_admin? || false
  end
end
