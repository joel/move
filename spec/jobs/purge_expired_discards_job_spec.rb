# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeExpiredDiscardsJob do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:) }

  before { allow(Organization).to receive(:pluck).with(:slug).and_return([Apartment::Tenant.current]) }

  it "hard-deletes discards past the retention window per tenant, keeping fresh ones" do
    expired = create(:item, move:, box:)
    fresh = create(:item, move:, box:)
    travel_to((Discardable::RETENTION + 1.day).ago) { Items::Delete.new.call(item: expired, actor:) }
    Items::Delete.new.call(item: fresh, actor:)

    described_class.perform_now

    expect(Item.with_discarded.exists?(expired.id)).to be(false)
    expect(Item.with_discarded.exists?(fresh.id)).to be(true)
  end

  it "skips a slug whose tenant schema is already dropped and still sweeps the rest" do
    # Account-deletion race: Accounts::Delete drops the schema before deleting the
    # Organization row, so the registry can briefly list a schema-less slug.
    allow(Organization).to receive(:pluck).with(:slug).and_return(["ghost-tenant", Apartment::Tenant.current])
    expired = create(:item, move:, box:)
    travel_to((Discardable::RETENTION + 1.day).ago) { Items::Delete.new.call(item: expired, actor:) }

    expect { described_class.perform_now }.not_to raise_error

    expect(Item.with_discarded.exists?(expired.id)).to be(false)
  end
end
