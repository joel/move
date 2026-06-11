# frozen_string_literal: true

# A captured image for a Box (Domain §4.9). Phase 1 is image-only. The file is an
# Active Storage attachment; recognition runs read it. No crop/bounding-box data
# is ever stored. Lives in the tenant schema (no organization_id).
class Media < ApplicationRecord
  MEDIA_TYPES = %w[image].freeze
  CAPTURED_VIA = %w[web mcp].freeze

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
  has_one_attached :image

  validates :media_type, inclusion: { in: MEDIA_TYPES }
  validates :captured_via, inclusion: { in: CAPTURED_VIA }
  validates :captured_at, presence: true
  validates :image, presence: true
  validate :image_must_be_an_image
  validate :image_within_size_limit

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
  def image_within_size_limit
    return unless image.attached?
    return if image.blob.byte_size <= MAX_IMAGE_BYTES

    errors.add(:image, :too_large, max: MAX_IMAGE_BYTES_LABEL)
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
