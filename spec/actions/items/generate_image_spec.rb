# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::GenerateImage do
  let(:move) { create(:move, image_provider: "fake") } # Fake adapter: a real PNG, no network
  let(:box) { create(:box, move:) }
  let(:item) { create(:item, :manual, move:, box:, name: "Brass lamp") }

  it "generates an image, attaches it as the item's source_media, and emits the event" do
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(item:, actor: create(:user))

    expect(result).to be_success
    item.reload
    aggregate_failures do
      expect(item.source_media).to be_present
      expect(item.source_media.image).to be_attached
      expect(item.source_media.captured_via).to eq("generated")
      expect(item.source_media.box).to eq(box) # in THIS box, so a reload renders it as a photo card
      expect(Rails.event).to have_received(:notify).with("item.image_generated", hash_including(item_id: item.id))
    end
  end

  it "is an idempotent no-op when the item already has a source photo (never clobbers)" do
    item.update!(source_media: create(:media, move:, box:))

    expect(described_class.new.call(item:).failure).to eq(:already_has_image)
  end

  it "fails without attaching when the provider errors (best-effort, no half-written item)" do
    boom = instance_double(ImageProviders::Fake)
    allow(boom).to receive(:generate).and_raise(ProviderHttp::Error, "429 rate limit")
    allow(ImageProviders).to receive(:for_move).and_return(boom)

    result = described_class.new.call(item:)

    expect(result.failure).to eq(:generation_failed)
    expect(item.reload.source_media_id).to be_nil
  end

  it "refuses to run on an archived (read-only) move" do
    move.update!(status: "archived")
    expect(described_class.new.call(item:).failure).to eq(:move_archived)
  end

  it "clears the claim on success (so the card leaves the generating state)" do
    item.update!(image_generating_at: Time.current) # claimed by the controller before enqueue

    described_class.new.call(item:)

    expect(item.reload.image_generating_at).to be_nil
    expect(item.source_media&.image).to be_attached
  end

  it "releases the claim on failure so a retry can re-claim immediately" do
    item.update!(image_generating_at: Time.current)
    boom = instance_double(ImageProviders::Fake)
    allow(boom).to receive(:generate).and_raise(ProviderHttp::Error, "boom")
    allow(ImageProviders).to receive(:for_move).and_return(boom)

    described_class.new.call(item:)

    expect(item.reload.image_generating_at).to be_nil
    expect(item.source_media_id).to be_nil
  end
end
