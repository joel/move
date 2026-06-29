# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::GenerateImageJob do
  let(:move) { create(:move, image_provider: "fake") }
  let(:box) { create(:box, move:) }
  let(:item) { create(:item, :manual, move:, box:) }
  let(:tenant) { Apartment::Tenant.current }

  it "generates the image (delegates to the action under the restored tenant)" do
    described_class.new.perform(item.id, tenant: tenant)

    expect(item.reload.source_media&.image).to be_attached
  end

  it "emits image_generation_failed when generation fails, leaving the item untouched" do
    boom = instance_double(ImageProviders::Fake)
    allow(boom).to receive(:generate).and_raise(ProviderHttp::Error, "boom")
    allow(ImageProviders).to receive(:for_move).and_return(boom)
    allow(Rails.event).to receive(:notify)

    described_class.new.perform(item.id, tenant: tenant)

    expect(item.reload.source_media_id).to be_nil
    expect(Rails.event).to have_received(:notify)
      .with("item.image_generation_failed", hash_including(item_id: item.id))
  end

  it "no-ops when the item already has a source photo" do
    item.update!(source_media: create(:media, move:, box:))

    expect { described_class.new.perform(item.id, tenant: tenant) }
      .not_to(change { item.reload.source_media_id })
  end
end
