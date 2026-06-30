# frozen_string_literal: true

# Provision a curated onboarding sample Move for every new organization (#432) as
# an event-driven side effect of org creation, never inline in the auth path. The
# subscriber enqueues a tenancy-aware job that builds the sample from committed demo
# assets (no AI call) and reveals it live on the Moves index.
Rails.application.config.after_initialize do
  Rails.event.subscribe(DemoData::ProvisionSubscriber.new) { |event| event[:name] == "organization.created" }
end
