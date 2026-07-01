# frozen_string_literal: true

module MediaVariants
  # Pre-generates (and persists) every defined display variant for a Media so no
  # surface ever pays the cold libvips transform on first view (#316). Active
  # Storage generates the :thumb/:detail variants lazily on first request
  # (Media#image, Phase 42 #299); calling `.processed` here materialises and
  # stores them ahead of time.
  #
  # Idempotent: `.processed` no-ops (a cheap storage existence check, no
  # transform) when the variant already exists. Best-effort — ANY processing or
  # storage failure is logged and skipped rather than raised: the transform can
  # fail with a libvips/ImageProcessing error (corrupt master) as well as an
  # ActiveStorage error, and the only consequence is the variant falling back to
  # lazy generation on first view (the pre-#316 behaviour). Swallowing here also
  # stops the background job retrying forever against a permanently bad blob.
  # Used by the capture subscriber's background job and the `images:prewarm`
  # backfill.
  class Prewarm
    # Mirror the variant names declared on Media#image. Kept in sync by the
    # MediaVariants::Prewarm spec, which asserts it matches the model.
    VARIANTS = %i[thumb detail].freeze

    def self.call(media) = new.call(media)

    # Returns the number of variants ensured present (warmed or already warm).
    def call(media)
      return 0 unless media&.image&.attached?

      VARIANTS.count { |variant| process(media, variant) }
    end

    private

    def process(media, variant)
      variant_record = media.image.variant(variant)
      variant_record.processed
      Rails.logger.debug { "[media_variants:prewarm] success media #{media.id} #{variant}" }
      true
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- best-effort prewarm; lazy generation is the fallback
      Rails.logger.warn { "[media_variants:prewarm] skip media #{media.id} #{variant}: #{e.class}: #{e.message}" }
      false
    end
  end
end
