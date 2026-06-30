# frozen_string_literal: true

module DemoData
  # Builds the onboarding sample Move off the signup path (#432). Restores the
  # Apartment tenant (jobs never inherit the request's Current/tenant), provisions
  # the sample, persists the org's terminal demo_data_status, then broadcasts the
  # reveal to the Moves index. Enqueued by DemoData::ProvisionSubscriber on
  # `organization.created`. Organization is a public/excluded model, so it resolves
  # before and inside the tenant switch alike.
  class ProvisionJob < ApplicationJob
    queue_as :default

    def perform(organization_id, tenant:)
      organization = Organization.find_by(id: organization_id)
      return unless organization

      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        provision(organization, tenant)
      end
    end

    private

    def provision(organization, tenant)
      owner = organization_owner(organization)
      return unless owner

      result = DemoData::Provision.new.call(owner: owner)
      finalize(organization, result)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- best-effort: a provisioning failure marks the org failed and reveals a fallback card, never crashing the worker or stranding the user
      Rails.logger.error("[demo_data] provision failed for #{tenant}: #{e.class}: #{e.message}")
      mark(organization, "failed")
    end

    def organization_owner(organization)
      user_id = organization.organization_memberships.where(role: "owner").pick(:user_id)
      User.find_by(id: user_id)
    end

    def finalize(organization, result)
      case result
      in Dry::Monads::Success(_move)
        mark(organization, "provisioned")
      in Dry::Monads::Failure(_)
        mark(organization, "failed")
      end
    end

    # Persist the terminal status BEFORE broadcasting so a page that loads after the
    # broadcast reads the right state (no stuck placeholder if the broadcast is lost).
    def mark(organization, status)
      organization.update!(demo_data_status: status)
      DemoData::Reveal.broadcast(organization)
    end
  end
end
