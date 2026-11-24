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

  it "purges the replaced blob and keeps a single attachment" do
    old_blob_id = media.image.blob.id

    expect(retake).to be_success

    expect(ActiveStorage::Blob.exists?(old_blob_id)).to be(false)
    expect(ActiveStorage::Attachment.where(record: media, name: "image").count).to eq(1)
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

  it "re-runs recognition when asked, swapping the image inside the guarded enqueue (#929)" do
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_return(true)
    allow(RecognitionRuns::Enqueue).to receive(:new).and_call_original
    old_blob_id = media.image.blob.id

    expect(retake(rerun_recognition: true)).to be_success

    # A re-scan run (#897), created through the guarded path (#919).
    expect(RecognitionRuns::Enqueue).to have_received(:new)
    expect(media.recognition_runs.sole).to have_attributes(status: "queued", rescan: true)
    expect(media.reload.image.blob.id).not_to eq(old_blob_id)
  end

  it "keeps the swap and still emits media.retaken when the re-scan job can't be queued (#871)" do
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_return(false)
    allow(Rails.event).to receive(:notify).and_call_original

    expect(retake(rerun_recognition: true).failure).to eq(:enqueue_failed)
    expect(Rails.event).to have_received(:notify).with("media.retaken", hash_including(media_id: media.id))
  end

  it "reports any other re-scan failure after the swap as :rescan_failed and still announces it (#933)" do
    allow(RecognitionRuns::Enqueue).to receive(:new).and_wrap_original do |original|
      original.call.tap { |enqueue| allow(enqueue).to receive(:create_run).and_return(Dry::Monads::Failure(:boom)) }
    end
    allow(Rails.event).to receive(:notify).and_call_original
    old_blob_id = media.image.blob.id

    expect(retake(rerun_recognition: true).failure).to eq(:rescan_failed)
    expect(media.reload.image.blob.id).not_to eq(old_blob_id)
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

  # #929 — the checks run again under the box and photo locks, before the
  # swap: a run that went in flight, or a box sealed, after the cheap
  # pre-check refuses the retake and leaves the image as it was.
  it "refuses, without swapping, a run that went in flight after the pre-check" do
    old_blob_id = media.image.blob.id
    action = described_class.new
    allow(action).to receive(:upload).and_wrap_original do |original, *args|
      create(:recognition_run, move:, box:, media:, status: "processing")
      original.call(*args)
    end

    result = nil
    # The blob stored for the refused retake is dropped again.
    expect { result = action.call(media:, actor: user, file: upload) }.not_to change(ActiveStorage::Blob, :count)

    expect(result.failure).to eq(:recognition_in_flight)
    expect(media.reload.image.blob.id).to eq(old_blob_id)
  end

  # The new file is stored before anything is written: attaching an IO would
  # upload it after the ready flags (and a re-scan run) had committed.
  it "writes nothing when storing the new image fails" do
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_return(true)
    media.update!(image_unavailable: true)
    old_blob_id = media.image.blob.id
    allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(Errno::ENOSPC)

    expect { retake(rerun_recognition: true) }.to raise_error(Errno::ENOSPC)

    media.reload
    expect(media).to have_attributes(image_unavailable: true)
    expect(media.image.blob.id).to eq(old_blob_id)
    expect(media.recognition_runs).to be_empty
  end

  # #956 — create_and_upload! saves the blob row before the storage write.
  it "leaves no blob row behind when storing the new image fails" do
    media # stored before the failure is stubbed
    allow(ActiveStorage::Blob.service).to receive(:upload).and_raise(Errno::ENOSPC)

    expect { expect { retake }.to raise_error(Errno::ENOSPC) }.not_to change(ActiveStorage::Blob, :count)
    expect(media.reload.image).to be_attached
  end

  # #955 — purging the replaced or unused blob is best-effort cleanup: a queue
  # that refuses every job must not fail or mask the retake.
  context "when the queue refuses every job" do
    before do
      media # created (and its image stored) before the queue goes down
      allow(Rails.event).to receive(:notify).and_call_original
      fail_every_enqueue
    end

    it "still returns the committed retake and emits media.retaken" do
      old_blob_id = media.image.blob.id

      expect(retake).to be_success
      expect(media.reload.image.blob.id).not_to eq(old_blob_id)
      expect(Rails.event).to have_received(:notify).with("media.retaken", hash_including(media_id: media.id))
    end

    it "still reports a re-scan that couldn't be queued as :enqueue_failed and emits media.retaken" do
      expect(retake(rerun_recognition: true).failure).to eq(:enqueue_failed)
      expect(media.recognition_runs.sole).to have_attributes(status: "failed", rescan: true)
      expect(Rails.event).to have_received(:notify).with("media.retaken", hash_including(media_id: media.id))
    end

    it "still returns the original refusal when the unused blob can't be purged" do
      action = described_class.new
      allow(action).to receive(:upload).and_wrap_original do |original, *args|
        create(:recognition_run, move:, box:, media:, status: "processing")
        original.call(*args)
      end

      expect(action.call(media:, actor: user, file: upload).failure).to eq(:recognition_in_flight)
      expect(Rails.event).not_to have_received(:notify).with("media.retaken", anything)
    end
  end

  it "refuses a re-scan, without swapping, when the box was sealed after the pre-check" do
    old_blob_id = media.image.blob.id
    action = described_class.new
    allow(action).to receive(:upload).and_wrap_original do |original, *args|
      Box.find(box.id).update!(status: "sealed")
      original.call(*args)
    end

    result = action.call(media:, actor: user, file: upload, rerun_recognition: true)

    expect(result.failure).to eq(:rescan_wrong_phase)
    expect(media.reload.image.blob.id).to eq(old_blob_id)
    expect(media.recognition_runs).to be_empty
  end
end
