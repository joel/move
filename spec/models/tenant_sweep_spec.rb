# frozen_string_literal: true

require "rails_helper"

RSpec.describe TenantSweep do
  let(:tenant) { Apartment::Tenant.current }

  def sweep
    seen = []
    described_class.in_each_tenant { |slug| seen << [slug, Apartment::Tenant.current] }
    seen
  end

  it "yields every registered slug with that tenant's schema active" do
    allow(Organization).to receive(:pluck).with(:slug).and_return([tenant])

    expect(sweep).to eq([[tenant, tenant]])
  end

  it "yields nothing when no organization is registered" do
    allow(Organization).to receive(:pluck).with(:slug).and_return([])

    expect(sweep).to eq([])
  end

  it "skips and logs a slug whose schema is missing, then sweeps the rest" do
    # Account-deletion race: the schema is dropped before the Organization row.
    allow(Organization).to receive(:pluck).with(:slug).and_return(["ghost-tenant", tenant])
    allow(Rails.logger).to receive(:warn)

    expect(sweep).to eq([[tenant, tenant]])
    expect(Rails.logger).to have_received(:warn).with(/ghost-tenant/)
  end

  it "propagates any other error raised by the block" do
    allow(Organization).to receive(:pluck).with(:slug).and_return([tenant, tenant])
    calls = 0

    expect do
      described_class.in_each_tenant do
        calls += 1
        raise ArgumentError, "boom"
      end
    end.to raise_error(ArgumentError, "boom")
    expect(calls).to eq(1)
  end

  it "propagates a TenantNotFound raised inside the block instead of skipping" do
    allow(Organization).to receive(:pluck).with(:slug).and_return([tenant, tenant])
    allow(Rails.logger).to receive(:warn)
    calls = 0

    expect do
      described_class.in_each_tenant do
        calls += 1
        Apartment::Tenant.switch("ghost-tenant") { nil }
      end
    end.to raise_error(Apartment::TenantNotFound)
    expect(calls).to eq(1)
    expect(Rails.logger).not_to have_received(:warn)
  end

  it "restores the previous tenant after the sweep" do
    allow(Organization).to receive(:pluck).with(:slug).and_return(["ghost-tenant", tenant])

    expect { sweep }.not_to(change(Apartment::Tenant, :current))
  end
end
