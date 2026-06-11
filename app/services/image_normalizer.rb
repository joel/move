# frozen_string_literal: true

require "marcel"
require "stringio"

# NB: ruby-vips (`require "vips"`) is loaded lazily inside #transcode, not here —
# it dlopens libvips at require time, and only the transcode path actually needs
# it. Requiring it at load would make boot/eager-load fail anywhere libvips is
# absent (e.g. the bare CI runner) even for the PNG/JPEG/WEBP pass-through path.

# Normalizes an uploaded image to a format the browser AND the recognition
# vision providers can both handle. Captures accept photos from a file input or
# the MCP base64 tool; the formats people actually have (notably iPhone HEIC)
# aren't renderable in most browsers or readable by OpenAI/Anthropic vision.
#
# Rather than reject them (the #78 stopgap) we transcode the decodable ones to
# JPEG on the way in, so the stored blob is always browser- and provider-safe
# (the 5 display surfaces serve the original blob directly to <img>). The
# content type is sniffed from the bytes (Marcel), not trusted from the client.
#
#   - native (JPEG/PNG/WEBP)            → returned unchanged
#   - transcodable (HEIC/HEIF/AVIF/
#     TIFF/BMP/GIF)                     → decoded (first frame), auto-rotated,
#                                         re-encoded as JPEG
#   - anything else (SVG, PDF, …) or a
#     file that won't decode            → raises UnsupportedFormat
#
# libvips ships the HEIF/AVIF/TIFF decoders in the app image (libde265 + dav1d);
# see doc/project/ai-providers.md. There is deliberately no SVG/vector path.
class ImageNormalizer
  NATIVE = %w[image/jpeg image/png image/webp].freeze
  # Includes the HEIC/HEIF *sequence* brands (image/heic-sequence,
  # image/heif-sequence) that Marcel sniffs from Live Photo / burst files —
  # libvips decodes their first frame just like the still variants.
  TRANSCODABLE = %w[
    image/heic image/heic-sequence image/heif image/heif-sequence
    image/avif image/tiff image/bmp image/gif
  ].freeze
  JPEG_QUALITY = 88

  class UnsupportedFormat < StandardError; end

  # @param attachable [ActionDispatch::Http::UploadedFile, Rack::Test::UploadedFile,
  #   Hash] the upload (an UploadedFile, or the {io:, filename:, content_type:}
  #   attachable hash the MCP tool builds).
  # @return the original attachable (native) or a JPEG attachable hash (transcoded).
  # @raise [UnsupportedFormat] for non-image / vector / undecodable input.
  def self.call(attachable) = new(attachable).call

  def initialize(attachable)
    @attachable = attachable
  end

  def call
    # Detect from the CONTENT (magic) only — never the client-supplied type or
    # filename. The MCP add_media tool defaults content_type to "image/jpeg" and
    # filename to "capture.jpg", so trusting either would let a HEIC upload pass
    # as an already-safe JPEG and get stored unconverted.
    type = Marcel::MimeType.for(StringIO.new(bytes))
    return @attachable if NATIVE.include?(type)
    return transcode(type) if TRANSCODABLE.include?(type)

    raise UnsupportedFormat, "Unsupported image format: #{type}"
  end

  private

  def transcode(type)
    require "vips"
    # access: :sequential keeps memory flat for large photos; first frame only
    # for animated GIF/HEIF; autorot bakes EXIF orientation; strip drops metadata.
    jpeg = Vips::Image.new_from_buffer(bytes, "", access: :sequential)
                      .autorot
                      .jpegsave_buffer(Q: JPEG_QUALITY, strip: true)
    { io: StringIO.new(jpeg), filename: "#{File.basename(filename, ".*")}.jpg", content_type: "image/jpeg" }
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

  # Only used to name the transcoded output blob — never to decide the type.
  def filename
    if @attachable.is_a?(Hash) then @attachable[:filename].to_s
    elsif @attachable.respond_to?(:original_filename) then @attachable.original_filename.to_s
    else "upload"
    end
  end
end
