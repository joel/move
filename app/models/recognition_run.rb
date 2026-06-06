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
end
