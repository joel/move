# frozen_string_literal: true

# Links a User to an Organization. `account_admin` may manage Organization
# settings and invitations. This is NOT a Move role (those live on
# MoveMembership) — see Domain Spec §4.
class OrganizationMembership < ApplicationRecord
  belongs_to :organization
  belongs_to :user

  validates :user_id, uniqueness: { scope: :organization_id }
end
