# frozen_string_literal: true

# Joins a User to an Organization with a role. Lives in the shared `public`
# schema (excluded from tenant scoping) alongside Organization and User.
class OrganizationMembership < ApplicationRecord
  ROLES = %w[owner admin member].freeze

  belongs_to :organization
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :organization_id }
end
