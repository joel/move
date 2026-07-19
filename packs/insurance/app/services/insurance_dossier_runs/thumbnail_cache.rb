# frozen_string_literal: true

module InsuranceDossierRuns
  # #702 — downloads and downscales item photos for the dossier PDF, memoized
  # per Media so a photo shared by many items (one box capture → many detected
  # items) is fetched and processed exactly once. Passed into InsuranceDossierPdf
  # duck-typed (the root PDF class never references a pack constant, keeping the
  # dependency direction pack → root).
  #
  # The stored master is already a ≤2048px EXIF-stripped JPEG (ImageNormalizer),
  # but at thumbnail size that is still ~200-400 KB per unique photo; downscaling
  # to MAX_EDGE keeps a full dossier in the tens of megabytes. Edge-transform
  # URLs (MediaVariants::TransformUrl) are unusable here — a job needs bytes, not
  # a browser-facing URL — so this is the one sanctioned blob.download path.
  class ThumbnailCache
    MAX_EDGE = 320
    JPEG_QUALITY = 75

    def initialize
      @cache = {}
    end

    # Thumbnail JPEG bytes for the media, or nil when there is no usable image
    # (no media, detached/corrupt master #563, or storage lost the blob) — the
    # PDF renders its drawn placeholder for nil.

    #: (untyped media) -> String?
    def fetch(media)
      return nil if media.nil?

      @cache.fetch(media.id) { @cache[media.id] = build(media) }
    end

    private

    #: (untyped media) -> String?
    def build(media)
      return nil unless media.image_displayable?

      downscale(media.image.blob.download)
    rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
      nil
    end

    # The recognition_providers/base.rb#downscale_jpeg recipe: autorotate, scale
    # the long edge down, strip metadata. The re-encode doubles as the
    # gatekeeper for Prawn: bytes vips cannot read (malformed masters — Prawn
    # dies on those with an unrescuable NoMethodError, not UnsupportedImageType)
    # become nil → the drawn placeholder. The vips-absent check is a `defined?`
    # guard, NOT a rescue — `rescue NameError` would also swallow NoMethodError
    # (a subclass) from inside the vips chain and hand Prawn unverified raw
    # bytes, defeating the quarantine.

    #: (String raw) -> String?
    def downscale(raw)
      return raw unless defined?(Vips) # vips absent — the master is a plain normalized JPEG

      img = Vips::Image.new_from_buffer(raw, "").autorot
      scale = MAX_EDGE.to_f / [img.width, img.height].max
      img = img.resize(scale) if scale < 1.0
      img.jpegsave_buffer(Q: JPEG_QUALITY, strip: true)
    rescue StandardError # rubocop:disable Move/BroadRescue -- unreadable bytes → placeholder, never a failed run
      nil
    end
  end
end
