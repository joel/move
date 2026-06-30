# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemoData::ProvisionSubscriber do
  let(:organization) { create(:organization) }

  def event(name: "organization.created", payload: { organization_id: organization.id, slug: organization.slug })
    { name: name, payload: payload }
  end

  before { allow(DemoData::ProvisionJob).to receive(:perform_later) }

  it "enqueues the provision job and marks the org provisioning" do
    described_class.new.emit(event)

    expect(DemoData::ProvisionJob).to have_received(:perform_later).with(organization.id, tenant: organization.slug)
    expect(organization.reload.demo_data_status).to eq("provisioning")
  end

  it "ignores unrelated events" do
    described_class.new.emit(event(name: "move.created", payload: {}))

    expect(DemoData::ProvisionJob).not_to have_received(:perform_later)
  end

  it "does nothing when auto-provisioning is suppressed (e.g. during seeds)" do
    DemoData.auto_provision = false

    described_class.new.emit(event)

    expect(DemoData::ProvisionJob).not_to have_received(:perform_later)
    expect(organization.reload.demo_data_status).to be_nil
  ensure
    DemoData.auto_provision = true
  end

  it "never raises out of the synchronous signup path" do
    allow(DemoData::ProvisionJob).to receive(:perform_later).and_raise(StandardError, "queue down")

    expect { described_class.new.emit(event) }.not_to raise_error
  end
end
