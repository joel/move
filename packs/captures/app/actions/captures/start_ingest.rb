# frozen_string_literal: true

# pack_public: true -- public API of packs/captures: the async web capture entry
# point (CapturesController). Kept in its layer; the sigil exposes it past
# enforce_privacy. See packwerk-boundaries.md.

module Captures
  # Async web capture entry point (#545): stores the raw upload to a blob,
  # creates a PENDING Media, and enqueues Captures::IngestJob to normalize +
  # attach + recognise off the request. Contrast Captures::Create, which does all
  # of that synchronously (still used by the MCP API path, where an API client
  # wants the finished Media back). The capture POST returns as soon as the row +
  # job exist, so the tile renders immediately as a placeholder and fills in over
  # ActionCable.
  class StartIngest < BaseAction
    #: (box: untyped, file: untyped, captured_by: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(box:, file:, captured_by:)
      yield ensure_writable(box.move)
      return Failure(:not_capturable) unless box.capturable?
      return Failure(:no_file) if file.blank?
      return Failure(:image_too_large) if oversize?(file)
      return Failure(:unsupported_image) unless image_bytes?(file)

      blob = yield store_raw(file)
      media = yield create_pending(box)
      IngestJob.perform_later(media.id, blob.id, captured_by_id: captured_by&.id, tenant: Apartment::Tenant.current)
      Success(media)
    end

    private

    # Cheap up-front reject before we store bytes; ImageNormalizer re-checks in
    # the job as the storage backstop.

    #: (untyped file) -> bool
    def oversize?(file)
      size = file.try(:size)
      size.present? && size > Media::MAX_IMAGE_BYTES
    end

    # Sniff the magic bytes (never the client-declared type) so an obviously
    # non-image is rejected up front — no orphaned pending row. Mirrors
    # McpUploadsController: any raster image/*, but not SVG (markup, not a raster
    # the pipeline can transcode). HEIC/TIFF/etc. pass here and are transcoded in
    # the job by ImageNormalizer.

    #: (untyped file) -> bool
    def image_bytes?(file)
      io = file.try(:open) || file
      content_type = Marcel::MimeType.for(io).to_s
      io.rewind if io.respond_to?(:rewind)
      content_type.start_with?("image/") && content_type != "image/svg+xml"
    end

    # Persist the raw upload as-is; IngestJob downloads it, normalizes (sniff →
    # transcode → optimise), attaches the master, and purges this reserved blob.
    # identify: false — never trust the client content type; the job sniffs.

    #: (untyped file) -> Dry::Monads::Result[untyped, untyped]
    def store_raw(file)
      blob = ActiveStorage::Blob.create_and_upload!(
        io: file.try(:open) || file,
        filename: file.try(:original_filename).presence || "capture",
        identify: false
      )
      Success(blob)
    rescue ActiveStorage::IntegrityError
      Failure(:invalid_upload)
    end

    #: (untyped box) -> Dry::Monads::Result[untyped, untyped]
    def create_pending(box)
      media = box.media.create!(
        move: box.move, media_type: "image", captured_via: "web",
        captured_at: Time.current, status: "pending"
      )
      Success(media)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end
  end
end
