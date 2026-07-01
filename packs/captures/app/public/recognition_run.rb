# frozen_string_literal: true

# One provider execution attempt for one Media (Domain §4.10). Never exposes
# vendor response structure: only a sanitized error and provider-independent
# operational metadata. Retry creates a *new* run.
class RecognitionRun < ApplicationRecord
  STATUSES = %w[queued processing succeeded partially_succeeded failed].freeze
  TERMINAL = %w[succeeded partially_succeeded failed].freeze

  belongs_to :move
  belongs_to :box
  belongs_to :media
  has_many :recognition_suggestions, dependent: :destroy

  validates :provider, presence: true
  validates :status, inclusion: { in: STATUSES }

  def processing?
    status == "processing"
  end

  def failed?
    status == "failed"
  end

  def terminal?
    TERMINAL.include?(status)
  end

  # Coarse classification of a failure for user-facing copy. Pure derivation from
  # the already-sanitized error_message — no business logic, no side effects.
  # Quota is checked before rate_limit because some vendors (OpenAI's
  # `insufficient_quota`) report an exhausted plan as HTTP 429.
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

  def error_detail
    msg = error_message.to_s
    return unless msg.match?(TRANSPORT_PREFIX)

    msg.sub(TRANSPORT_PREFIX, "").presence
  end
end
