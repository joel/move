# frozen_string_literal: true

module DemoData
  # On `organization.created` (every signup — passwordless + Google), kick off the
  # onboarding sample-Move provisioning (#432): enqueue the tenancy-aware job, then
  # mark the org "provisioning" so the Moves index shows the live placeholder. Runs
  # synchronously inside Organizations::Create#emit_event (after its transaction
  # commits), so it must never break org creation — hence the rescue.
  class ProvisionSubscriber
    def emit(event)
      return unless event[:name] == "organization.created"
      return unless DemoData.auto_provision?

      provision(event[:payload])
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 subscriber must not break org creation / signup
      Rails.logger.warn("[demo_data] provision enqueue failed: #{e.class}: #{e.message}")
    end

    private

    def provision(payload)
      organization_id = payload&.dig(:organization_id)
      slug = payload&.dig(:slug)
      return if organization_id.blank? || slug.blank?

      organization = Organization.find_by(id: organization_id)
      return unless organization

      # Mark "provisioning" BEFORE enqueuing. A fast/inline worker can run the job
      # and write the terminal status before this method returns; if we enqueued
      # first and then wrote "provisioning", we'd clobber that terminal value and
      # strand the org on the placeholder forever. If the enqueue then fails, roll
      # the marker back so the index falls back to the normal empty state rather
      # than a placeholder that can never be revealed.
      organization.update!(demo_data_status: "provisioning")
      enqueue_or_rollback(organization, slug)
    end

    def enqueue_or_rollback(organization, slug)
      DemoData::ProvisionJob.perform_later(organization.id, tenant: slug)
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- a failed enqueue must not strand the index on the placeholder
      organization.update!(demo_data_status: nil)
      raise e
    end
  end
end
