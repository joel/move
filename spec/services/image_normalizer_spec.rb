# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageNormalizer do
  def fixture(name) = Rails.root.join("spec/fixtures/files", name)
  def upload(name, type) = Rack::Test::UploadedFile.new(fixture(name), type)
  def jpeg?(bytes) = Marcel::MimeType.for(StringIO.new(bytes)) == "image/jpeg"

  it "returns a native (JPEG/PNG/WEBP) upload unchanged" do
    file = upload("sample_image.png", "image/png")
    expect(described_class.call(file)).to be(file)
  end

  it "transcodes a TIFF upload to a JPEG attachable" do
    result = described_class.call(upload("sample.tiff", "image/tiff"))

    expect(result).to include(content_type: "image/jpeg", filename: "sample.jpg")
    expect(jpeg?(result[:io].read)).to be(true)
  end

  it "transcodes an MCP-style attachable hash (io/filename/content_type)" do
    bytes = fixture("sample.tiff").binread
    attachable = { io: StringIO.new(bytes), filename: "photo.tiff", content_type: "image/tiff" }

    result = described_class.call(attachable)

    expect(result[:content_type]).to eq("image/jpeg")
    expect(jpeg?(result[:io].read)).to be(true)
  end

  it "sniffs the real type from the bytes, not the (mislabeled) declared type" do
    # PNG bytes mislabeled as TIFF must still be treated as the native PNG.
    file = upload("sample_image.png", "image/tiff")
    expect(described_class.call(file)).to be(file)
  end

  it "raises UnsupportedFormat for a vector/non-raster image (SVG)" do
    expect { described_class.call(upload("sample.svg", "image/svg+xml")) }
      .to raise_error(described_class::UnsupportedFormat)
  end

  it "raises UnsupportedFormat when a transcodable type won't actually decode" do
    attachable = { io: StringIO.new("not really a tiff"), filename: "broken.tiff", content_type: "image/tiff" }
    expect { described_class.call(attachable) }.to raise_error(described_class::UnsupportedFormat)
  end
end
