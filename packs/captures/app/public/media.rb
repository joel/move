# frozen_string_literal: true

# A captured image for a Box (Domain §4.9). Phase 1 is image-only. The file is an
# Active Storage attachment; recognition runs read it. No crop/bounding-box data
# is ever stored. Lives in the tenant schema (no organization_id).
class Media < ApplicationRecord
  # Soft-deletable: a photo is discarded when packing-removing the last item it
  # sourced (Items::Remove). The cascade-trace columns already exist; `default_scope
  # { kept }` then hides a deleted photo from the gallery. No media is discarded by
  # any other path, so the scope is a no-op for existing queries.
  include Discardable

  MEDIA_TYPES = %w[image].freeze
  # web/mcp = a real captured upload; generated = an AI image made for a manual
  # item (#416). "generated" is deliberately kept out of the recognition/prewarm
  # pipeline (which keys off media.captured), so a generated photo never re-enters
  # recognition.
  CAPTURED_VIA = %w[web mcp generated].freeze

  # Ingest lifecycle (#545). The web capture POST creates a `pending` row and
  # enqueues Captures::IngestJob, which normalizes → attaches → flips to `ready`
  # (or `failed` if the upload can't be processed). The synchronous paths
  # (MCP, AI-generated) attach in-request and create the row already `ready`.
  # A `pending` row has no image yet — the image-presence validation is gated on
  # `ready` so the row can exist before its blob is attached.
  STATUSES = %w[pending ready failed].freeze
  ACTIVE = %w[pending].freeze
  TERMINAL = (STATUSES - ACTIVE).freeze

  # The formats actually *stored* — what every display surface and the vision
  # providers can read. This is a storage backstop: uploads are normalized by
  # ImageNormalizer before attach (HEIC/TIFF/etc. transcoded to JPEG, unsupported
  # rejected), so by the time a blob reaches here it is already one of these.
  SUPPORTED_IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze

  # Upper bound on a capture image. Enforced up front by ImageNormalizer (before
  # the upload is read into memory / transcoded) and re-checked here as a
  # storage backstop. A phone photo is a few MB; 25 MB is generous headroom.
  MAX_IMAGE_BYTES = 25 * 1024 * 1024
  MAX_IMAGE_BYTES_LABEL = ActiveSupport::NumberHelper.number_to_human_size(MAX_IMAGE_BYTES)

  belongs_to :move
  belongs_to :box
  has_many :recognition_runs, dependent: :destroy
  has_many :recognition_suggestions, dependent: :destroy
  # Items this photo sourced that are STILL co-located in its box — the discard
  # cascade for Photos::Delete. Scoped to the photo's own box on purpose (#577):
  # an item moved to another box keeps its source_media_id (Items::Move), but
  # deleting the photo must NOT reach into that other box, whose phase guard this
  # action doesn't hold (it might be sealed/unpacking). Moved-away items survive
  # with a now-dangling source_media (optional, valid) — mirrors Photos::Move's
  # co-located rule (#317). Not an AR dependency (source_media survives the photo);
  # the soft-delete cascade discards these under one batch so a single
  # Discards::CascadeRestore brings the whole set back.
  has_many :co_located_sourced_items, ->(media) { where(box_id: media.box_id) },
           class_name: "Item", foreign_key: :source_media_id, dependent: nil
  discard_cascade_to :co_located_sourced_items
  # The attachment is the optimised master (≤2048px JPEG, written by
  # ImageNormalizer). Display sizes are produced on demand at Cloudflare's edge —
  # `MediaVariants::TransformUrl.for(media, :thumb|:detail)` mints a signed URL to
  # the media-transform Worker (#572) — so the master is the ONLY stored object.
  # No in-app Active Storage variants: the variant pipeline (declarations +
  # MediaVariants::Prewarm) was decommissioned with the edge cutover.
  has_one_attached :image

  validates :media_type, inclusion: { in: MEDIA_TYPES }
  validates :captured_via, inclusion: { in: CAPTURED_VIA }
  validates :captured_at, presence: true
  validates :status, inclusion: { in: STATUSES }
  # A pending row exists before its blob is attached (#545); only a ready media
  # must carry an image. The format/size backstops below still apply once one is.
  validates :image, presence: true, if: :ready?
  validate :image_must_be_an_image
  validate :image_within_size_limit

  #: () -> bool
  def pending? = status == "pending"

  #: () -> bool
  def ready? = status == "ready"

  #: () -> bool
  def ingest_failed? = status == "failed"

  # Whether a display surface can actually render this photo: an attached master
  # that is still readable. `image_unavailable` is set (#563) when the master blob
  # became unrecoverable (the #560 corruption); rendering a variant off it would
  # 500 and retry regeneration on every view, so surfaces fall back to a
  # placeholder instead. `image_unavailable?` is provided by the boolean column.

  #: () -> bool
  def image_displayable? = image.attached? && !image_unavailable?

  # Base64 of the tiny blur-up preview stamped into blob metadata at ingest
  # (ImageNormalizer, #681; `images:lqip` backfills legacy blobs). nil until
  # generated — surfaces then keep their plain placeholder.

  #: () -> String?
  def image_lqip = image.attached? ? image.blob.metadata["lqip"] : nil

  #: () -> void
  def image_must_be_an_image
    return unless image.attached?

    content_type = image.content_type.to_s
    return if SUPPORTED_IMAGE_TYPES.include?(content_type)

    if content_type.start_with?("image/")
      errors.add(:image, :unsupported_format, formats: supported_formats_label)
    else
      errors.add(:image, :not_an_image)
    end
  end

  # Backstop for the up-front ImageNormalizer size check.

  #: () -> void
  def image_within_size_limit
    return unless image.attached?
    return if image.blob.byte_size <= MAX_IMAGE_BYTES

    errors.add(:image, :too_large, max: MAX_IMAGE_BYTES_LABEL)
  end

  # "JPEG, PNG, WEBP, GIF" — for the user-facing rejection message.

  #: () -> String
  def supported_formats_label
    SUPPORTED_IMAGE_TYPES.map { |type| type.split("/").last.upcase }.join(", ")
  end

  scope :recent_first, -> { order(captured_at: :desc) }
  scope :ready, -> { where(status: "ready") }
  # Keyset cursors for a (captured_at, id)-ordered walk in either direction —
  # the gallery's "Load more" pages (#718). The id half is essential: bulk
  # captures share captured_at, so a time-only cursor would skip or repeat every
  # row on the page-boundary timestamp (the activity feed's #194 lesson). The
  # tuple comparison advances past exactly the last row seen; id casts to uuid
  # so the bound string compares as a uuid, not text.
  scope :captured_before, ->(time, id) { where("(captured_at, id) < (?, ?::uuid)", time, id) }
  scope :captured_after, ->(time, id) { where("(captured_at, id) > (?, ?::uuid)", time, id) }
  # Rows whose image ingest hasn't settled yet — pending (in flight) or failed.
  # The reaper (purge_abandoned_uploads) uses `pending` + age to clear orphans.
  scope :pending, -> { where(status: "pending") }
  # Real captures only — excludes AI-generated images (#416), which never had a
  # recognition run and so must stay out of the per-photo review walk + the
  # "all reviewed" badge.
  scope :not_generated, -> { where.not(captured_via: "generated") }

  # The latest run's status drives the per-image recognition badge.

  #: () -> String?
  def recognition_state
    recognition_runs.order(created_at: :desc).first&.status
  end

  # Has this photo produced an item? MOVE-wide, not box-scoped: Items::Move keeps
  # source_media_id when an item moves to another box, so the photo is still
  # "recognized" even though no item lives in its original box. `with_discarded`:
  # a soft-deleted item still counts, so discarding it never re-flags the photo as
  # orphaned (which would offer recovery and let it re-source a duplicate — #198).

  #: () -> bool
  def sourced_item?
    move.items.with_discarded.exists?(source_media_id: id)
  end

  # Single source of truth for "this photo needs recovery": recognition produced
  # nothing to act on — no item references it AND it has no suggestions (a
  # conflict-only run records suggestions but no item, by the no-overwrite rule, so
  # offering a manual add would recreate that avoided duplicate). Used by the
  # recovery surface (RecoveriesController, ItemsController#create) and mirrored by
  # the bulk BoxesController#recoverable_media_ids query.

  #: () -> bool
  def orphaned?
    !sourced_item? && !recognition_suggestions.exists?
  end

  # A run is queued or processing — recognition may still materialize items, so
  # recovery mutations (re-run, manual-add binding) must wait until it settles.

  #: () -> bool
  def recognition_in_flight?
    recognition_runs.exists?(status: %w[queued processing])
  end
end
