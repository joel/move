# frozen_string_literal: true

# An Organization is the tenant boundary. Its globally-unique `slug` is the
# subdomain (`<slug>.move.workeverywhere.docker`). All Move-scoped data hangs off
# an Organization; cross-organization access is blocked (non-disclosing 404).
class Organization < ApplicationRecord
  # Subdomain labels reserved for the platform itself — never assignable as slugs.
  RESERVED_SLUGS = %w[
    move www mail storage bucket api admin app assets cdn static
    auth login help support status billing
  ].freeze

  # RFC-1123 subdomain label: lowercase alphanumeric + hyphens, 2–63 chars,
  # no leading/trailing hyphen.
  SLUG_FORMAT = /\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/

  belongs_to :created_by_user, class_name: "User", optional: true

  has_many :organization_memberships, dependent: :destroy
  has_many :users, through: :organization_memberships

  before_validation :normalize_slug

  validates :name, presence: true
  validates :slug,
            presence: true,
            uniqueness: { case_sensitive: false },
            length: { in: 2..63 },
            format: { with: SLUG_FORMAT },
            exclusion: { in: RESERVED_SLUGS }

  private

  def normalize_slug
    self.slug = slug.to_s.strip.downcase.presence
  end
end
