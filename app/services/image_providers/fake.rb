# frozen_string_literal: true

require "base64"
begin
  require "vips"
rescue LoadError
  # ruby-vips is optional; without it Fake falls back to an embedded 1x1 PNG.
end

module ImageProviders
  # Deterministic, network-free generator for tests, local development and the
  # demo seed. Produces a real (attachable, variant-able) PNG — a plain sage
  # square — so the placeholder→image card swap is exercisable with no vendor key.
  class Fake < Base
    DEFAULT_MODEL = "fake-image-1"
    # Sage-tinted solid; an actual raster so ActiveStorage :thumb/:detail variants
    # process cleanly (mirrors a real generated image).
    FILL = [122, 138, 115].freeze
    # Minimal valid 1x1 PNG, used only when ruby-vips is unavailable.
    PIXEL = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="

    def generate(prompt:) # rubocop:disable Lint/UnusedMethodArgument
      Result.new(provider: "fake", model: DEFAULT_MODEL, image_bytes: png_bytes, content_type: "image/png")
    end

    private

    def png_bytes
      Vips::Image.black(512, 512, bands: 3).add(FILL).cast(:uchar).pngsave_buffer
    rescue StandardError # rubocop:disable Move/BroadRescue -- vips absent (NameError)/encode failure → 1x1 fallback
      Base64.strict_decode64(PIXEL)
    end
  end
end
