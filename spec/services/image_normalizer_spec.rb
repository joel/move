# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageNormalizer do
  def fixture(name) = Rails.root.join("spec/fixtures/files", name)
  def upload(name, type) = Rack::Test::UploadedFile.new(fixture(name), type)
  def jpeg?(bytes) = Marcel::MimeType.for(StringIO.new(bytes)) == "image/jpeg"

  # [width, height] of an encoded image, via libvips.
  def dims(bytes)
    require "vips"
    img = Vips::Image.new_from_buffer(bytes, "")
    [img.width, img.height]
  end

  # Build encoded test images in-memory (avoids committing multi-MB fixtures).
  # Returns nil when libvips is absent so the dependent specs can skip.
  # Gaussian noise (not a solid fill) so JPEG can't crush it to near-nothing —
  # keeps "downscaled output is smaller than the original" a meaningful assertion.
  def vips_jpeg(width, height)
    require "vips"
    Vips::Image.gaussnoise(width, height, mean: 128, sigma: 50).cast("uchar").jpegsave_buffer(Q: 92)
  rescue LoadError
    nil
  end

  def vips_rgba_png(width, height)
    require "vips"
    Vips::Image.black(width, height, bands: 4).add([200, 100, 50, 128]).cast("uchar").pngsave_buffer
  rescue LoadError
    nil
  end

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

  # Skip on a dev host that lacks the codec plugin, but FAIL in CI — there the
  # plugins are installed on purpose (see ci.yml), so a missing decoder is a
  # regression in codec coverage, not an environment quirk, and must not silently
  # downgrade these real-bytes specs to pending.
  def require_decode!(name)
    return if vips_decodes?(name)
    raise "libvips cannot decode #{name}: codec plugin missing in CI (regression)" if ENV["CI"]

    skip "libvips here lacks the codec plugin to decode #{name}"
  end

  it "optimises a native (JPEG/PNG/WEBP) upload into a JPEG master (no longer passed through)" do
    result = described_class.call(upload("sample_image.png", "image/png"))

    expect(result).to include(content_type: "image/jpeg", filename: "sample_image.jpg")
    expect(jpeg?(result[:io].read)).to be(true)
  end

  it "down-scales an oversized photo to the master long-edge cap" do
    bytes = vips_jpeg(3000, 2000) || skip("libvips unavailable")
    attachable = { io: StringIO.new(bytes), filename: "huge.jpg", content_type: "image/jpeg" }

    result = described_class.call(attachable)
    out = result[:io].read

    expect(jpeg?(out)).to be(true)
    expect(dims(out).max).to eq(ImageNormalizer::MASTER_IMAGE_EDGE) # 3000 → 2048
    expect(out.bytesize).to be < bytes.bytesize
  end

  it "does not up-scale an image already within the cap" do
    bytes = vips_jpeg(120, 90) || skip("libvips unavailable")
    attachable = { io: StringIO.new(bytes), filename: "small.jpg", content_type: "image/jpeg" }

    out = described_class.call(attachable)[:io].read

    expect(dims(out)).to eq([120, 90]) # unchanged, never enlarged
  end

  it "flattens a transparent (alpha) PNG to JPEG without error" do
    bytes = vips_rgba_png(300, 300) || skip("libvips unavailable")
    attachable = { io: StringIO.new(bytes), filename: "alpha.png", content_type: "image/png" }

    out = described_class.call(attachable)[:io].read

    expect(jpeg?(out)).to be(true)
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
    # PNG bytes mislabeled as TIFF must still be decoded as the real PNG and
    # optimised to a valid JPEG (not mangled by trusting the declared type).
    result = described_class.call(upload("sample_image.png", "image/tiff"))
    expect(jpeg?(result[:io].read)).to be(true)
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
    require_decode!("sample.heic")

    result = described_class.call(upload("sample.heic", "image/heic"))

    expect(result).to include(content_type: "image/jpeg")
    expect(jpeg?(result[:io].read)).to be(true)
  end

  it "transcodes a real AVIF image to JPEG end to end" do
    require_decode!("sample.avif")

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
