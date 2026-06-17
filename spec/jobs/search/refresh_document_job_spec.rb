# frozen_string_literal: true

require "rails_helper"

RSpec.describe Search::RefreshDocumentJob do
  let(:move) { create(:move) }
  let(:tenant) { Apartment::Tenant.current }

  it "refreshes the item's search document" do
    item = create(:item, move: move)

    described_class.perform_now(item.id, tenant: tenant)

    expect(item.reload.search_document).to be_present
  end

  it "is safe when the item was since deleted" do
    expect { described_class.perform_now(SecureRandom.uuid, tenant: tenant) }.not_to raise_error
  end

  context "when part of a tracked indexing run (#239)" do
    it "records the item as completed against the run" do
      item = create(:item, move: move)
      run = create(:indexing_run, :processing, move: move, total_count: 1)

      described_class.perform_now(item.id, tenant: tenant, indexing_run_id: run.id)

      run.reload
      expect(run.completed_count).to eq(1)
      expect(run.status).to eq("completed")
    end

    it "still advances the run for a since-deleted item (nothing to embed)" do
      run = create(:indexing_run, :processing, move: move, total_count: 1)

      described_class.perform_now(SecureRandom.uuid, tenant: tenant, indexing_run_id: run.id)

      expect(run.reload.completed_count).to eq(1)
    end
  end
end
