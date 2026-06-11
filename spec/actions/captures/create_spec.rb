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
end
