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

    # A re-scan run (#897), created through the guarded path (#919).
    expect(enqueue).to have_received(:call).with(media:, rescan: true, guard: instance_of(Proc))
  end

  it "keeps the swap and still emits media.retaken when the re-scan job can't be queued (#871)" do
    enqueue = instance_double(RecognitionRuns::Enqueue, call: Dry::Monads::Failure(:enqueue_failed))
    allow(RecognitionRuns::Enqueue).to receive(:new).and_return(enqueue)
    allow(Rails.event).to receive(:notify).and_call_original

    expect(retake(rerun_recognition: true).failure).to eq(:enqueue_failed)
    expect(Rails.event).to have_received(:notify).with("media.retaken", hash_including(media_id: media.id))
  end

  it "leaves a re-scan the capture screen's Retry accepts when its job can't be queued (#897)" do
    create(:item, move:, box:, source_media: media, name: "Coffee maker") # reviewed items from the old image
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_return(false)

    expect(retake(rerun_recognition: true).failure).to eq(:enqueue_failed)
    run = media.recognition_runs.order(:created_at).last
    expect(run).to have_attributes(status: "failed", rescan: true)

    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_return(true)
    expect(RecognitionRuns::Retry.new.call(run:)).to be_success
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

  # #919 — the guarded enqueue re-checks the box phase under the box and
  # photo locks. A box sealed after the up-front check (here, during the swap)
  # refuses the re-scan with its own code: the swap has persisted, so the
  # caller can say so, and the retake is still announced.
  it "re-checks the box phase under the lock" do
    allow(Rails.event).to receive(:notify).and_call_original
    allow(media).to receive(:update!).and_wrap_original do |original, *args, **kw|
      Box.where(id: box.id).update_all(status: "sealed") # rubocop:disable Rails/SkipsModelValidations
      original.call(*args, **kw)
    end

    expect(retake(rerun_recognition: true).failure).to eq(:replaced_rescan_wrong_phase)
    expect(media.recognition_runs).to be_empty
    expect(Rails.event).to have_received(:notify).with("media.retaken", hash_including(media_id: media.id))
  end

  # A run that went in flight after the up-front check may be scanning the
  # OLD image. The re-scan still creates its run, which is then the latest,
  # so Process supersedes the older one instead of letting it put old-image
  # items on the new photo.
  it "still re-scans when a run went in flight during the swap, so the newer run supersedes it" do
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_return(true)
    concurrent = nil
    allow(media).to receive(:update!).and_wrap_original do |original, *args, **kw|
      concurrent = create(:recognition_run, move:, box:, media:, status: "processing")
      original.call(*args, **kw)
    end

    expect(retake(rerun_recognition: true)).to be_success
    expect(RecognitionRun.latest_for?(concurrent)).to be(false)
    expect(RecognitionRun.latest_for(media.id).pick(:rescan)).to be(true)
  end
end
