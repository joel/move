# frozen_string_literal: true

# A captured image for a Box (Domain §4.9). Phase 1 is image-only. The file is an
# Active Storage attachment; recognition runs read it. No crop/bounding-box data
# is ever stored. Lives in the tenant schema (no organization_id).
class Media < ApplicationRecord
  MEDIA_TYPES = %w[image].freeze
  CAPTURED_VIA = %w[web mcp].freeze

  # Formats the recognition vision providers (OpenAI/Anthropic) can actually
  # read. The app must not accept an image it can only fail on later: anything
  # else (HEIC, TIFF, SVG, BMP…) is rejected at upload rather than producing a
  # consistently-failing recognition run once a real provider is enabled.
  # Transcoding unsupported formats to JPEG is tracked as a follow-up.
  SUPPORTED_IMAGE_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

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

    content_type = image.content_type.to_s
    return if SUPPORTED_IMAGE_TYPES.include?(content_type)

    if content_type.start_with?("image/")
      errors.add(:image, :unsupported_format, formats: supported_formats_label)
    else
      errors.add(:image, :not_an_image)
    end
  end

  # "JPEG, PNG, WEBP, GIF" — for the user-facing rejection message.
  def supported_formats_label
    SUPPORTED_IMAGE_TYPES.map { |type| type.split("/").last.upcase }.join(", ")
  end

  scope :recent_first, -> { order(captured_at: :desc) }

  # The latest run's status drives the per-image recognition badge.
  def recognition_state
    recognition_runs.order(created_at: :desc).first&.status
  end
end
