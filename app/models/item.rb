# frozen_string_literal: true

# An inventory item in exactly one Box (Domain §4.12). Created by recognition
# (auto_confirmed/pending_review) or manually. An item is just a name —
# category, tags, quantity and fragility were all removed across the
# simplification epic. No value, bounding box, or crop fields. The hidden
# `family` column (#626) feeds search/clustering and has exactly ONE rendering
# consumer: the insurance declaration's theme grouping (#702).
class Item < ApplicationRecord
  # Field-level history (Logidze) over the editable column (name) — powers the
  # activity feed's revert (PR3). The whitelist trigger ignores discard/system
  # columns, so deleting never churns a version.
  has_logidze
  # Soft delete (Domain §11) — the *deletion* axis, orthogonal to the unpacking
  # `presence_state: removed` axis below. `default_scope { kept }` hides deleted
  # items from every query (counts, search, listings).
  include Discardable

  CREATED_VIA = %w[recognition manual mcp].freeze
  REVIEW_STATES = %w[pending_review auto_confirmed confirmed needs_correction].freeze
  PRESENCE_STATES = %w[in_box removed].freeze

  belongs_to :move
  belongs_to :box
  belongs_to :source_media, class_name: "Media", optional: true
  # D8 hybrid-search projection (one row per item; lexical + optional embedding).
  has_one :search_document, class_name: "ItemSearchDocument", dependent: :destroy
  # Raw uuid back-reference (no FK; set when materialized from a suggestion).
  # No belongs_to to avoid a circular dependency with RecognitionSuggestion.

  validates :name, presence: true
  validates :created_via, inclusion: { in: CREATED_VIA }
  validates :review_state, inclusion: { in: REVIEW_STATES }
  validates :presence_state, inclusion: { in: PRESENCE_STATES }

  scope :in_box, -> { where(presence_state: "in_box") }
  # Items unpacked / removed from their box (D10 unpacking "Unpacked" section).
  scope :removed, -> { where(presence_state: "removed") }
  # Items still awaiting review, in either unreviewed state (needs_correction has
  # no write path today but is a live read path). in_box: a removed item (e.g. a
  # false-positive) must not linger in pending counts. The ONE definition shared
  # by the box badge, the boxes-home summary, the move cards and the review queue.
  scope :unreviewed, -> { in_box.where(review_state: %w[pending_review needs_correction]) }
  scope :ordered, -> { order(created_at: :asc) }
  # Confirmed/auto-confirmed items still in their box — the default searchable set
  # (excludes needs_correction and removed; Domain §7.4).
  scope :searchable, -> { in_box.where(review_state: %w[confirmed auto_confirmed]) }

  #: () -> bool
  def removed?
    presence_state == "removed"
  end

  # A claim older than this is treated as abandoned (a crashed generation job),
  # so the item is generatable again and the UI stops showing "generating" (#416).
  IMAGE_CLAIM_TTL = 5.minutes

  # Whether an image generation is currently in flight (a fresh, non-stale claim)
  # — drives the card's generating state on reload, and the generatable guard.

  #: () -> bool
  def image_generating?
    # Bind once: separate attribute reads defeat nil-narrowing. For a timestamp
    # column, present? ≡ !nil? — the nil? form is what narrows.
    claimed_at = image_generating_at
    !claimed_at.nil? && claimed_at > IMAGE_CLAIM_TTL.ago
  end

  # Atomically claim this item for image generation (#416): a single UPDATE that
  # succeeds only when no photo exists and no fresh claim is held. Concurrent
  # callers race on one row — exactly one wins. Returns the claim timestamp on a
  # win (the controller passes it to the job as a token), else nil. Reclaimable
  # after IMAGE_CLAIM_TTL so a crashed job self-heals; taken at the synchronous
  # entry point (the controller) so the in-flight state is observable on render.

  #: () -> untyped
  def claim_image_generation!
    now = Time.current
    rows = self.class.where(id: id, source_media_id: nil)
               .where("image_generating_at IS NULL OR image_generating_at < ?", IMAGE_CLAIM_TTL.ago)
               .update_all(image_generating_at: now) # rubocop:disable Rails/SkipsModelValidations
    rows == 1 ? now : nil
  end

  # Whether the item still holds this exact claim — the job verifies its token
  # before the (paid) vendor call, so a stale-reclaimed duplicate (queue backed up
  # past the TTL → a second click re-claimed) bails instead of double-spending
  # (#416). Second precision is ample: a duplicate only arises ≥ TTL apart.

  #: (untyped claimed_at) -> bool
  def holds_image_claim?(claimed_at)
    image_generating_at.present? && image_generating_at.to_i == claimed_at.to_i
  end
end
