require "rails_helper"

RSpec.describe Captures::Create do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:, status: "packing") }

  def upload(name = "sample_image.png", type = "image/png")
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files", name), type)
  end

  it "creates media, runs recognition inline, and lands items" do
    result = described_class.new.call(box:, file: upload, captured_by: user)

    expect(result).to be_success
    media = result.value!
    expect(media.image).to be_attached
    expect(box.media.count).to eq(1)
    # :inline adapter ran the pipeline, so items + a succeeded run exist.
    expect(box.recognition_runs.last.status).to eq("succeeded")
    expect(box.items.count).to eq(3)
  end

  it "succeeds with the saved photo and emits media.captured when recognition can't be queued (#871)" do
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_raise(SolidQueue::Job::EnqueueError)
    allow(Rails.event).to receive(:notify).and_call_original

    result = described_class.new.call(box:, file: upload, captured_by: user)

    expect(result.value!).to eq(box.media.sole)
    media = box.media.sole
    expect(media.recognition_runs.sole.status).to eq("failed")
    expect(Rails.event).to have_received(:notify).with("media.captured", hash_including(media_id: media.id))
  end

  it "blocks capture into a sealed box" do
    sealed = create(:box, :with_room, move:, status: "sealed")
    result = described_class.new.call(box: sealed, file: upload, captured_by: user)

    expect(result).to be_failure
    expect(result.failure).to eq(:not_capturable)
  end

  it "fails honestly when no file is provided (no offline queue)" do
    result = described_class.new.call(box:, file: nil, captured_by: user)
    expect(result).to be_failure
    expect(result.failure).to eq(:no_file)
  end

  it "rejects a non-image upload" do
    result = described_class.new.call(box:, file: upload("not.txt", "text/plain"), captured_by: user)
    expect(result).to be_failure
    expect(result.failure).to eq(:unsupported_image)
  end

  it "transcodes a non-native image (TIFF) to JPEG before storing" do
    result = described_class.new.call(box:, file: upload("sample.tiff", "image/tiff"), captured_by: user)

    expect(result).to be_success
    expect(result.value!.image.content_type).to eq("image/jpeg")
  end

  # #955 — dropping the reserved direct-upload blob is best-effort cleanup.
  context "when the queue refuses every job" do
    def reserved_signed_id(name, type)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: Rails.root.join("spec/fixtures/files", name).open, filename: name, content_type: type
      )
      blob.signed_id(purpose: described_class.signed_id_purpose(move))
    end

    it "still returns the saved capture and emits media.captured" do
      signed_id = reserved_signed_id("sample_image.png", "image/png")
      allow(Rails.event).to receive(:notify).and_call_original
      fail_every_enqueue

      result = described_class.new.call(box:, signed_id:, captured_by: user)

      expect(result.value!).to eq(box.media.sole)
      expect(Rails.event).to have_received(:notify).with("media.captured", hash_including(media_id: result.value!.id))
    end

    it "still returns the rejection of an unsupported direct upload" do
      signed_id = reserved_signed_id("not.txt", "text/plain")
      fail_every_enqueue

      expect(described_class.new.call(box:, signed_id:, captured_by: user).failure).to eq(:unsupported_image)
    end
  end

  it "rejects an upload larger than the size limit" do
    stub_const("Media::MAX_IMAGE_BYTES", 5)
    result = described_class.new.call(box:, file: upload, captured_by: user)

    expect(result).to be_failure
    expect(result.failure).to eq(:image_too_large)
    expect(box.media.count).to eq(0)
  end
end
