# frozen_string_literal: true

# A captured image for a Box (Domain §4.9). Phase 1 is image-only. The file is an
# Active Storage attachment; recognition runs read it. No crop/bounding-box data
# is ever stored. Lives in the tenant schema (no organization_id).
class Media < ApplicationRecord
  MEDIA_TYPES = %w[image].freeze
  CAPTURED_VIA = %w[web mcp].freeze

  belongs_to :move
  belongs_to :box
  has_many :recognition_runs, dependent: :destroy
  has_many :recognition_suggestions, dependent: :destroy
  has_one_attached :image

  validates :media_type, inclusion: { in: MEDIA_TYPES }
  validates :captured_via, inclusion: { in: CAPTURED_VIA }
  validates :captured_at, presence: true
  validates :image, presence: true
  validate :image_must_be_an_image

  def image_must_be_an_image
    return unless image.attached?
    return if image.content_type.to_s.start_with?("image/")

    errors.add(:image, :not_an_image)
  end

  scope :recent_first, -> { order(captured_at: :desc) }

  # The latest run's status drives the per-image recognition badge.
  def recognition_state
    recognition_runs.order(created_at: :desc).first&.status
  end
end
