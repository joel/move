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

  validates :name, presence: true
  validates :slug,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: SLUG_FORMAT }
end
