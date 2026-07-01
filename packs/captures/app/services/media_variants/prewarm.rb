# frozen_string_literal: true

module MediaVariants
  # Pre-generates (and persists) every defined display variant for a Media so no
  # surface ever pays the cold libvips transform on first view (#316). Active
  # Storage generates the :thumb/:detail variants lazily on first request
  # (Media#image, Phase 42 #299); calling `.processed` here materialises and
  # stores them ahead of time.
  #
  # Idempotent: `.processed` no-ops (a cheap DB existence check, no transform)
  # when the variant record already exists. Best-effort — ANY processing or
  # storage failure is logged and skipped rather than raised: the transform can
  # fail with a libvips/ImageProcessing error (corrupt master) as well as an
  # ActiveStorage error, and the only consequence is the variant falling back to
  # lazy generation on first view (the pre-#316 behaviour). Swallowing here also
  # stops the background job retrying forever against a permanently bad blob.
  # Used by the capture subscriber's background job and the `images:prewarm`
  # backfill.
  #
  # Repair mode (opt-in, `repair: true` — used by `images:repair`, #486) additionally
  # heals *orphaned* variants: a record whose row exists but whose file is gone from
  # object storage (isolated SeaweedFS loss). `.processed` alone can't fix those —
  # it checks only that the row is present (`VariantWithRecord#processed?`), never
  # that the file exists, so a broken variant is served forever. Repair drops the
  # stale record first, then `.processed` rebuilds it from the master. It costs a
  # storage existence check per variant, so it stays off the per-capture hot path.
  class Prewarm
    # Mirror the variant names declared on Media#image. Kept in sync by the
    # MediaVariants::Prewarm spec, which asserts it matches the model.
    VARIANTS = %i[thumb detail].freeze

    # Count of orphaned variants actually rebuilt (repair mode). Accumulates across
    # every `#call` on this instance, so `images:repair` can report how many broken
    # variants a run healed — distinct from the total "ensured present" count.
    attr_reader :repaired

    def self.call(media, repair: false) = new(repair:).call(media)

    def initialize(repair: false)
      @repair = repair
      @repaired = 0
    end

    # Returns the number of variants ensured present (warmed, repaired, or already
    # warm).
    def call(media)
      return 0 unless media&.image&.attached?

      VARIANTS.count { |variant| process(media, variant) }
    end

    private

    def process(media, variant)
      repair_orphan(media, variant) if @repair
      media.image.variant(variant).processed
      Rails.logger.debug { "[media_variants:prewarm] success media #{media.id} #{variant}" }
      true
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- best-effort prewarm; lazy generation is the fallback
      Rails.logger.warn { "[media_variants:prewarm] skip media #{media.id} #{variant}: #{e.class}: #{e.message}" }
      false
    end

    # Drop a variant record whose file is missing from storage so the subsequent
    # `.processed` rebuilds it. A healthy variant (record + file both present) is
    # left untouched — no needless re-transform.
    def repair_orphan(media, variant)
      variant_obj = media.image.variant(variant)
      stored = variant_obj.image # record&.image; nil when no record exists yet
      return if stored.nil?      # nothing stored — `.processed` will create it

      file = stored.blob
      return if file&.service&.exist?(file.key) # healthy — keep it

      Rails.logger.info { "[media_variants:prewarm] repairing orphaned #{variant} for media #{media.id}" }
      @repaired += 1
      variant_obj.destroy # deletes the stale record (+ any file)
      # `images:repair` loads media via `with_attached_image`, which PRELOADS the
      # master blob's `variant_records`. A direct `record.destroy` deletes the row
      # but leaves the destroyed object in that already-loaded collection, so the
      # following `.processed` would re-find it in memory, judge the variant
      # `processed?`, and skip the rebuild. Reset the association so `.processed`
      # re-queries, sees the row gone, and regenerates from the master.
      variant_obj.blob.variant_records.reset
    end
  end
end
