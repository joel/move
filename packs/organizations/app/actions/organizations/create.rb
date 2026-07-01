# frozen_string_literal: true

# pack_public: true -- public API of packs/organizations: creates an Organization + its tenant.
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Organizations
  # Creates an Organization (tenant registry row), makes the creator its owner,
  # and provisions the Apartment tenant schema. All in the public schema.
  class Create < BaseAction
    # Subdomains that route to the app/apex or sibling services, never tenants.
    RESERVED_SLUGS = %w[move mail storage bucket www app admin api].freeze

    def call(name:, slug:, owner:)
      slug = normalize(slug)
      yield ensure_available(slug)
      organization = yield persist(name, slug, owner)
      yield provision_tenant(organization)
      yield emit_event(organization)
      Success(organization)
    end

    private

    def normalize(slug)
      slug.to_s.downcase.strip
    end

    def ensure_available(slug)
      return Failure(:reserved_slug) if RESERVED_SLUGS.include?(slug)

      Success()
    end

    def persist(name, slug, owner)
      organization = nil
      ActiveRecord::Base.transaction do
        organization = Organization.create!(name: name, slug: slug)
        organization.organization_memberships.create!(user: owner, role: "owner")
      end
      Success(organization)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def provision_tenant(organization)
      Apartment::Tenant.create(organization.slug)
      Success()
    rescue Apartment::TenantExists
      Failure(:tenant_exists)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- cleanup orphan tenant row; returns Failure
      # The schema could not be created; do not leave an orphaned registry row.
      organization.destroy
      Failure(e.message)
    end

    def emit_event(organization)
      Rails.event.notify(
        "organization.created",
        organization_id: organization.id,
        slug: organization.slug
      )
      Success()
    end
  end
end
