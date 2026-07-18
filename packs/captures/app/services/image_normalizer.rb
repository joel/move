# frozen_string_literal: true

require "marcel"
require "stringio"
require "base64"

# NB: ruby-vips (`require "vips"`) is loaded lazily inside #optimize, not here —
# it dlopens libvips at require time. Requiring it at load would make boot/
# eager-load fail anywhere libvips is absent (e.g. a bare runner). A native
# upload still degrades to pass-through if libvips is genuinely missing.

# Normalizes AND optimises an uploaded image so the stored blob is a bounded,
# high-quality master the browser AND the recognition vision providers can both
# handle. Captures accept photos from a file input or the MCP direct upload; the
# formats people actually have (notably iPhone HEIC) aren't renderable in most
# browsers or readable by OpenAI/Anthropic vision, and a raw phone photo is 12MP+
# / several MB — far more than any surface displays (the gallery shows ~400px
# thumbnails; recognition re-downscales to 1536px) and wasteful to store.
#
# So every decodable image is decoded, auto-rotated, **down-scaled to a
# MASTER_IMAGE_EDGE long edge** (never up-scaled), alpha-flattened, and re-encoded
# as a stripped JPEG. The stored blob is therefore always browser- and
# provider-safe AND small; the display surfaces serve sized Active Storage
# *variants* off this master (Media#image :thumb/:detail). Stripping EXIF also
# drops GPS metadata (a privacy win). The content type is sniffed from the bytes
# (Marcel), never trusted from the client (Phase 42, #299).
#
#   - native (JPEG/PNG/WEBP)            → decoded, auto-rotated, down-scaled,
#                                         re-encoded as JPEG (NOT passed through)
#   - transcodable (HEIC/HEIF/AVIF/
#     TIFF/BMP/GIF)                     → same path (first frame for animated)
#   - anything else (SVG, PDF, …) or a
#     file that won't decode            → raises UnsupportedFormat
#
# libvips ships the HEIF/AVIF/TIFF decoders in the app image (libde265 + dav1d);
# see doc/project/ai-providers.md. There is deliberately no SVG/vector path. If
# libvips is genuinely absent, a native upload degrades to pass-through (still
# display/provider safe, just unoptimised) rather than failing the capture.
class ImageNormalizer
  NATIVE = %w[image/jpeg image/png image/webp].freeze
  # Includes the HEIC/HEIF *sequence* brands (image/heic-sequence,
  # image/heif-sequence) that Marcel sniffs from Live Photo / burst files —
  # libvips decodes their first frame just like the still variants.
  TRANSCODABLE = %w[
    image/heic image/heic-sequence image/heif image/heif-sequence
    image/avif image/tiff image/bmp image/gif
  ].freeze
  PROCESSABLE = (NATIVE + TRANSCODABLE).freeze
  JPEG_QUALITY = 85
  # LQIP (blur-up placeholder, #681): a tiny stripped JPEG stored as base64 in
  # blob metadata (~300-800 bytes) and inlined as a data URI under the real
  # image. 24px is enough structure once blurred; artifacts are hidden by the
  # blur, so quality stays low.
  LQIP_EDGE = 24
  LQIP_QUALITY = 50
  # Long-edge cap for the stored master. 2048 keeps full-screen viewing crisp on
  # retina/desktop while recognition re-downscales to 1536 with negligible loss;
  # a 12MP phone photo (~3-5MB) lands around 300-600KB. Display surfaces request
  # smaller variants still (Media :thumb 400px / :detail 1600px).
  MASTER_IMAGE_EDGE = 2048

  class UnsupportedFormat < StandardError; end
  class ImageTooLarge < StandardError; end

  # @param attachable [ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile,
  #   Hash] the upload (an UploadedFile, or the {io:, filename:, content_type:}
  #   attachable hash the MCP tool builds).
  # @return a JPEG attachable hash (the optimised master), or the original
  #   attachable unchanged when libvips is absent and the upload is already native.
  # @raise [ImageTooLarge] when the upload exceeds Media::MAX_IMAGE_BYTES.
  # @raise [UnsupportedFormat] for non-image / vector / undecodable input.
  def self.call(attachable) = new(attachable).call

  # Base64 of a tiny (LQIP_EDGE long-edge) stripped JPEG derived from any
  # vips-decodable bytes — the blur-up placeholder stored in blob metadata
  # (#681). thumbnail_buffer shrinks on load (cheap even for a full master,
  # which is how the images:lqip backfill uses it). Returns nil when the bytes
  # won't decode or libvips is unavailable — the caller just omits the key and
  # surfaces fall back to the plain placeholder.
  #: (String bytes) -> String?
  def self.lqip_base64(bytes)
    # The require gets its own rescue: referencing Vips::Error in a rescue
    # clause before libvips loaded would NameError on the constant.
    begin
      require "vips"
    rescue LoadError
      return nil
    end

    tiny = Vips::Image.thumbnail_buffer(bytes, LQIP_EDGE)
    tiny = tiny.flatten(background: 255) if tiny.has_alpha?
    Base64.strict_encode64(tiny.jpegsave_buffer(Q: LQIP_QUALITY, strip: true))
  rescue Vips::Error
    nil
  end

  def initialize(attachable)
    @attachable = attachable
  end

  def call
    # Reject oversized uploads from their reported size BEFORE reading the bytes
    # into memory or handing them to libvips (a decode/re-encode in the request).
    raise ImageTooLarge if reported_byte_size > Media::MAX_IMAGE_BYTES

    # Detect from the CONTENT (magic) only — never the client-supplied type or
    # filename. The MCP add_media tool defaults content_type to "image/jpeg" and
    # filename to "capture.jpg", so trusting either would let a HEIC upload pass
    # as an already-safe JPEG and get stored unconverted.
    type = Marcel::MimeType.for(StringIO.new(bytes))
    return optimize(type) if PROCESSABLE.include?(type)

    raise UnsupportedFormat, "Unsupported image format: #{type}"
  end

  private

  # Decode → auto-rotate → down-scale (never up-scale) → flatten alpha → JPEG.
  def optimize(type)
    require "vips"
    # access: :sequential keeps memory flat for large photos; first frame only
    # for animated GIF/HEIF; autorot bakes EXIF orientation before any strip.
    img   = Vips::Image.new_from_buffer(bytes, "", access: :sequential).autorot
    scale = MASTER_IMAGE_EDGE.to_f / [img.width, img.height].max
    img   = img.resize(scale) if scale < 1.0
    # PNG/WEBP transparency would render as black in JPEG — flatten onto white.
    img   = img.flatten(background: 255) if img.has_alpha?
    jpeg  = img.jpegsave_buffer(Q: JPEG_QUALITY, strip: true)
    # The pipeline just decoded the image, so record its dimensions as blob
    # metadata up front (analyzed: true skips the async AnalyzeJob round trip) —
    # display surfaces need real dimensions for lightbox slides (#675) and the
    # tiny blur-up preview (#681). LQIP is derived from the freshly-encoded
    # master bytes, NOT the sequential-access pipeline image (a second scan of
    # a sequential image raises in vips).
    metadata = { width: img.width, height: img.height, analyzed: true }
    lqip = self.class.lqip_base64(jpeg)
    metadata[:lqip] = lqip if lqip
    { io: StringIO.new(jpeg), filename: "#{File.basename(filename, ".*")}.jpg", content_type: "image/jpeg",
      metadata: }
  rescue LoadError
    # libvips genuinely unavailable. A native upload is already display/provider
    # safe, so store it unchanged (unoptimised); a transcodable one can't be made
    # safe without vips, so it must be rejected.
    raise UnsupportedFormat, "Cannot process #{type}: libvips unavailable" unless NATIVE.include?(type)

    @attachable
  rescue Vips::Error
    # The bytes claimed a decodable type but libvips couldn't read them
    # (truncated/corrupt). Treat as unsupported — never leak the vips detail.
    raise UnsupportedFormat, "Could not decode #{type} image"
  end

  def bytes
    @bytes ||=
      if @attachable.is_a?(Hash)
        io = @attachable.fetch(:io)
        io.rewind
        io.read.tap { io.rewind }
      else
        @attachable.rewind if @attachable.respond_to?(:rewind)
        @attachable.read.tap { @attachable.rewind if @attachable.respond_to?(:rewind) }
      end
  end

  # Size from the IO's own metadata (UploadedFile#size / StringIO#size) — no read.
  def reported_byte_size
    io = @attachable.is_a?(Hash) ? @attachable[:io] : @attachable
    io.respond_to?(:size) ? io.size.to_i : bytes.bytesize
  end

  # Only used to name the optimised output blob — never to decide the type.
  def filename
    if @attachable.is_a?(Hash) then @attachable[:filename].to_s
    elsif @attachable.respond_to?(:original_filename) then @attachable.original_filename.to_s
    else "upload"
    end
  end
end
