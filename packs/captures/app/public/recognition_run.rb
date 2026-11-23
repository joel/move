# frozen_string_literal: true

# One provider execution attempt for one Media (Domain §4.10). Never exposes
# vendor response structure: only a sanitized error and provider-independent
# operational metadata. Retry creates a *new* run.
class RecognitionRun < ApplicationRecord
  STATUSES = %w[queued processing succeeded partially_succeeded failed].freeze
  TERMINAL = %w[succeeded partially_succeeded failed].freeze
  IN_FLIGHT = %w[queued processing].freeze

  belongs_to :move
  belongs_to :box
  belongs_to :media
  has_many :recognition_suggestions, dependent: :destroy

  validates :provider, presence: true
  validates :status, inclusion: { in: STATUSES }

  # Each photo's LATEST run id, as a subquery (never loaded into Ruby — AGENTS.md
  # rule 5). `media` is anything `where(media_id:)` accepts: ids or a relation.
  # THE definition of "latest" (#902): newest created_at, id breaking a tie.
  # Process, Retry and Media#recognition_state all read it through
  # .latest_for / .latest_for? so they can't drift apart.
  scope :latest_ids_for, lambda { |media|
    where(media_id: media)
      .select("DISTINCT ON (recognition_runs.media_id) recognition_runs.id")
      .order("recognition_runs.media_id", "recognition_runs.created_at DESC", "recognition_runs.id DESC")
  }
  # The latest run of each photo, as rows (filter outside the DISTINCT ON).
  scope :latest_for, ->(media) { where(id: latest_ids_for(media)) }

  # Is `run` still its photo's latest run?

  #: (untyped run) -> bool
  def self.latest_for?(run)
    latest_for(run.media_id).exists?(id: run.id)
  end

  #: () -> bool
  def processing?
    status == "processing"
  end

  #: () -> bool
  def failed?
    status == "failed"
  end

  #: () -> bool
  def terminal?
    TERMINAL.include?(status)
  end

  # The kept items that show this run's photo was already turned into
  # inventory (#896), so a new run must not materialize it again: every kept
  # item sourced from the photo. A retake re-scan (`rescan`, #897) is meant to
  # layer suggestions over the items of an earlier image, so for it only the
  # items created since the current image was attached count.

  #: () -> untyped
  def materialized_items
    items = Item.kept.where(source_media_id: media_id)
    attached_at = image_attached_at if rescan?
    attached_at ? items.where(created_at: attached_at..) : items
  end

  # Coarse classification of a failure for user-facing copy. Pure derivation from
  # the already-sanitized error_message — no business logic, no side effects.
  # Quota is checked before rate_limit because some vendors (OpenAI's
  # `insufficient_quota`) report an exhausted plan as HTTP 429.

  #: () -> Symbol
  def error_category
    msg = error_message.to_s
    case msg
    when /no api key set/i then :missing_key
    when /quota|billing|insufficient_quota|credit balance/i then :quota
    when /rate.?limit|too many requests|\(429\)/i then :rate_limit
    when /api key|unauthorized|\(401\)|invalid x-api-key|permission/i then :auth
    when /timeout|timed out|connection|network|econnreset/i then :network
    else :generic
    end
  end

  # The vendor's human-readable detail, surfaced ONLY when the failure is a real
  # transport error ("RecognitionProviders::Openai request failed (429): <vendor
  # text>") — the prefix is stripped so a customer never sees adapter class names
  # or status codes. Any other message (model-drift "… returned no objects
  # array", a raw "OPENAI_API_KEY is not set", an ActiveRecord error) is internal
  # and returns nil, so callers fall back to the generic localized line instead
  # of leaking implementation detail.
  TRANSPORT_PREFIX = /\A\S+ request failed \(\d+\): /

  #: () -> String?
  def error_detail
    msg = error_message.to_s
    return unless msg.match?(TRANSPORT_PREFIX)

    msg.sub(TRANSPORT_PREFIX, "").presence
  end

  private

  # Read straight from the attachment row: the photo may be discarded, which
  # Media's kept default scope would hide from the association.

  #: () -> untyped
  def image_attached_at
    ActiveStorage::Attachment.where(record_type: "Media", record_id: media_id, name: "image").pick(:created_at)
  end
end
