# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::GenerateImageJob do
  let(:move) { create(:move, image_provider: "fake") }
  let(:box) { create(:box, move:) }
  let(:claim) { Time.current }
  # The controller claims before enqueuing; mirror that so the job's token matches.
  let(:item) { create(:item, :manual, move:, box:, image_generating_at: claim) }

  def run(claimed_at: claim.to_i)
    described_class.new.perform(item.id, tenant: Apartment::Tenant.current, claimed_at: claimed_at)
  end

  it "generates the image (delegates to the action under the restored tenant)" do
    run

    expect(item.reload.source_media&.image).to be_attached
  end

  it "emits image_generation_failed when generation fails, leaving the item untouched" do
    boom = instance_double(ImageProviders::Fake)
    allow(boom).to receive(:generate).and_raise(ProviderHttp::Error, "boom")
    allow(ImageProviders).to receive(:for_move).and_return(boom)
    allow(Rails.event).to receive(:notify)

    run

    expect(item.reload.source_media_id).to be_nil
    expect(Rails.event).to have_received(:notify)
      .with("item.image_generation_failed", hash_including(item_id: item.id))
  end

  it "no-ops when the item already has a source photo" do
    item.update!(source_media: create(:media, move:, box:))

    expect { run }.not_to(change { item.reload.source_media_id })
  end

  it "bails (no spend) when the item no longer holds this job's claim (stale-reclaim duplicate)" do
    # The queue backed up past the TTL and a second click re-claimed; this delayed
    # job's token no longer matches, so it must not call the provider.
    item.update!(image_generating_at: 2.minutes.from_now) # a distinctly newer claim
    allow(ImageProviders).to receive(:for_move)

    run(claimed_at: claim.to_i) # the OLD token

    expect(ImageProviders).not_to have_received(:for_move)
    expect(item.reload.source_media_id).to be_nil
  end
end
