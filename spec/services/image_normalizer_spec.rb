# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageNormalizer do
  def fixture(name) = Rails.root.join("spec/fixtures/files", name)
  def upload(name, type) = Rack::Test::UploadedFile.new(fixture(name), type)
  def jpeg?(bytes) = Marcel::MimeType.for(StringIO.new(bytes)) == "image/jpeg"

  # Whether the running libvips can actually decode a fixture — HEIC needs the
  # libheif HEVC plugin (libde265) and AVIF the AV1 plugin (aom/dav1d), which are
  # present in the app/CI image but not every dev host. Lets the real-bytes
  # decode specs skip (rather than fail) where the codec plugin is absent.
  def vips_decodes?(name)
    require "vips"
    # libvips is lazy — .avg forces actual pixel decode so a missing codec plugin
    # raises here rather than later during transcode.
    Vips::Image.new_from_buffer(fixture(name).binread, "").avg
    true
  rescue Vips::Error
    false
  end

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

  it "ignores the MCP default type/filename (image/jpeg + capture.jpg) and transcodes by content" do
    # The MCP add_media tool defaults a HEIC upload to content_type image/jpeg +
    # filename capture.jpg; the decision must come from the bytes, not that.
    bytes = fixture("sample.tiff").binread
    attachable = { io: StringIO.new(bytes), filename: "capture.jpg", content_type: "image/jpeg" }

    result = described_class.call(attachable)

    expect(result).not_to be(attachable)         # NOT passed through as a "native jpeg"
    expect(jpeg?(result[:io].read)).to be(true)  # actually transcoded to real JPEG
  end

  # --- Real-bytes verification for the modern phone formats (#128) ---

  it "sniffs a real HEIC photo as a heic/heif MIME type" do
    # Proves Marcel detects real HEIC bytes as a TRANSCODABLE type (no decoder needed).
    expect(Marcel::MimeType.for(fixture("sample.heic").open)).to match(%r{\Aimage/hei[cf]})
  end

  it "transcodes a real HEIC photo to JPEG end to end" do
    skip "libvips here lacks the libheif HEVC (libde265) decoder" unless vips_decodes?("sample.heic")

    result = described_class.call(upload("sample.heic", "image/heic"))

    expect(result).to include(content_type: "image/jpeg")
    expect(jpeg?(result[:io].read)).to be(true)
  end

  it "transcodes a real AVIF image to JPEG end to end" do
    skip "libvips here lacks the libheif AV1 (aom/dav1d) decoder" unless vips_decodes?("sample.avif")

    result = described_class.call(upload("sample.avif", "image/avif"))

    expect(result).to include(content_type: "image/jpeg")
    expect(jpeg?(result[:io].read)).to be(true)
  end

  it "transcodes HEIC/HEIF sequence brands (Live Photo/burst), not just the still variants" do
    # No HEIC encoder to build a real fixture, so drive the routing: a sequence
    # MIME (what Marcel sniffs from a Live Photo) must take the transcode path.
    %w[image/heic-sequence image/heif-sequence].each do |seq_type|
      allow(Marcel::MimeType).to receive(:for).and_return(seq_type)
      result = described_class.call(upload("sample.tiff", "image/tiff")) # real decodable bytes
      expect(result).to include(content_type: "image/jpeg")
    end
  end

  it "raises ImageTooLarge for an upload over the size limit (before reading/transcoding)" do
    stub_const("Media::MAX_IMAGE_BYTES", 5) # any real fixture exceeds 5 bytes
    expect { described_class.call(upload("sample_image.png", "image/png")) }
      .to raise_error(described_class::ImageTooLarge)
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
