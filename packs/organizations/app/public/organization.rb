# frozen_string_literal: true

# Tenant registry. Each Organization is an Apartment tenant (its own
# PostgreSQL schema named after the slug); this record lives in the shared
# `public` schema so it is reachable regardless of the active tenant.
#
# Provisioning the tenant schema and the owner membership is the job of
# `Organizations::Create` — never a model callback.
class Organization < ApplicationRecord
  # DNS label and PostgreSQL schema name: 2-63 chars, starts with a letter,
  # lowercase alphanumeric and hyphens, no trailing hyphen.
  SLUG_FORMAT = /\A[a-z][a-z0-9-]{0,61}[a-z0-9]\z/

  has_many :organization_memberships, dependent: :destroy
  has_many :users, through: :organization_memberships

  # The org an account is "primarily" in (#346): oldest membership first, slug as
  # a stable tiebreaker, so a multi-org user's fallback is deterministic.

  # @rbs skip
  def self.primary_for(user_id)
    joins(:organization_memberships)
      .where(organization_memberships: { user_id: user_id })
      .order(Arel.sql("organization_memberships.created_at ASC, organizations.slug ASC"))
      .first
  end

  # Is `user_id` a member of the org with this slug? (origin-handoff guard, #346)

  # @rbs skip
  def self.member?(user_id:, slug:)
    joins(:organization_memberships)
      .exists?(slug: slug, organization_memberships: { user_id: user_id })
  end

  validates :name, presence: true
  validates :slug,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: SLUG_FORMAT }
end
