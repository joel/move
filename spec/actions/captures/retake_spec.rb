# frozen_string_literal: true

require "rails_helper"

RSpec.describe Captures::Retake do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:, status: "packing") }
  let(:media) { create(:media, move:, box:) }

  def upload(name = "sample_image.png", type = "image/png")
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files", name), type)
  end

  def retake(photo: media, file: upload, rerun_recognition: false)
    described_class.new.call(media: photo, actor: user, file:, rerun_recognition:)
  end

  it "swaps the image, clears image_unavailable, and keeps the items" do
    media.update!(image_unavailable: true)
    item = create(:item, move:, box:, source_media: media)
    old_blob_id = media.image.blob.id

    expect(retake).to be_success

    media.reload
    expect(media.image).to be_attached
    expect(media.image.blob.id).not_to eq(old_blob_id) # a fresh master was attached
    expect(media.image_unavailable?).to be(false)
    expect(Item.kept.exists?(item.id)).to be(true) # items untouched
  end

  it "emits media.retaken (re-warms variants, not a fresh capture)" do
    allow(Rails.event).to receive(:notify).and_call_original

    retake

    expect(Rails.event).to have_received(:notify)
      .with("media.retaken", hash_including(media_id: media.id, move_id: move.id))
    expect(Rails.event).not_to have_received(:notify).with("media.captured", anything)
  end

  it "does not re-run recognition by default" do
    allow(RecognitionRuns::Enqueue).to receive(:new).and_call_original

    retake(rerun_recognition: false)

    expect(RecognitionRuns::Enqueue).not_to have_received(:new)
  end

  it "re-runs recognition when asked" do
    enqueue = instance_double(RecognitionRuns::Enqueue, call: Dry::Monads::Success())
    allow(RecognitionRuns::Enqueue).to receive(:new).and_return(enqueue)

    retake(rerun_recognition: true)

    expect(enqueue).to have_received(:call).with(media:)
  end

  it "is allowed in any phase (recovery of existing data)" do
    sealed = create(:box, :sealed, move:)
    photo = create(:media, move:, box: sealed)

    expect(retake(photo:)).to be_success
  end

  it "refuses a re-scan on a non-packing box (re-scan adds items) and doesn't swap" do
    sealed = create(:box, :sealed, move:)
    photo = create(:media, move:, box: sealed)
    old_blob_id = photo.image.blob.id

    result = retake(photo:, rerun_recognition: true)

    expect(result).to be_failure
    expect(result.failure).to eq(:rescan_wrong_phase)
    expect(photo.reload.image.blob.id).to eq(old_blob_id) # nothing swapped
  end

  it "refuses without a file" do
    result = retake(file: nil)
    expect(result).to be_failure
    expect(result.failure).to eq(:no_file)
  end

  it "refuses while a recognition run is still in flight" do
    create(:recognition_run, media:, status: "queued")

    result = retake
    expect(result).to be_failure
    expect(result.failure).to eq(:recognition_in_flight)
  end
end
