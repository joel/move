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
    # Binds a direct-upload signed_id to the Move (mirrors Captures::Create's MCP
    # purpose): CapturesController#direct_upload mints the blob's signed_id with it,
    # and #resolve_direct_upload verifies with it — so a token can only reserve a
    # blob for its own Move, and a leaked/replayed id can't attach elsewhere. The
    # tenant schema is included so an id from one Organization can never verify
    # under another. Distinct from the `mcp_media_upload` purpose (different path).
    # Singleton defs aren't supported by inline RBS yet; declared in sig/captures.rbs.

    # @rbs skip
    def self.signed_id_purpose(move)
      "web_media_upload/#{Apartment::Tenant.current}/#{move.id}"
    end

    #: (box: untyped, captured_by: untyped, ?file: untyped, ?signed_id: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(box:, captured_by:, file: nil, signed_id: nil)
      yield ensure_writable(box.move)
      return Failure(:not_capturable) unless box.capturable?

      blob = yield reserve_blob(box, file, signed_id)
      media = yield create_pending(box, blob.byte_size)
      IngestJob.perform_later(media.id, blob.id, captured_by_id: captured_by&.id, tenant: Apartment::Tenant.current)
      Success(media)
    end

    private

    # Either the raw bytes came through the app (`file`, server-proxied) or the
    # browser already PUT them straight to R2 and handed us a Move-scoped `signed_id`
    # (#572 direct upload). Direct upload skips the up-front byte sniff — the bytes
    # aren't local, and IngestJob's ImageNormalizer re-sniffs, size-caps, strips
    # EXIF/GPS and transcodes regardless (never bypassed) — but still cheaply
    # re-checks the known byte_size against the cap.

    #: (untyped box, untyped file, untyped signed_id) -> Dry::Monads::Result[untyped, untyped]
    def reserve_blob(box, file, signed_id)
      return resolve_direct_upload(box, signed_id) if signed_id.present?
      return Failure(:no_file) if file.blank?
      return Failure(:image_too_large) if oversize?(file)
      return Failure(:unsupported_image) unless image_bytes?(file)

      store_raw(file)
    end

    # The blob was created by CapturesController#direct_upload (validated + capped
    # there) and uploaded to R2 by the browser. Verify the Move-scoped purpose so
    # it can only be attached to its own Move, and re-assert the size cap.

    #: (untyped box, untyped signed_id) -> Dry::Monads::Result[untyped, untyped]
    def resolve_direct_upload(box, signed_id)
      blob = ActiveStorage::Blob.find_signed!(signed_id, purpose: self.class.signed_id_purpose(box.move)) # steep:ignore ArgumentTypeMismatch
      return Failure(:image_too_large) if blob.byte_size > Media::MAX_IMAGE_BYTES

      Success(blob)
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      Failure(:invalid_upload)
    end

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

    #: (untyped box, Integer raw_byte_size) -> Dry::Monads::Result[untyped, untyped]
    def create_pending(box, raw_byte_size)
      media = box.media.create!(
        move: box.move, media_type: "image", captured_via: "web",
        captured_at: Time.current, status: "pending",
        # The raw upload as the client sent it (downscaled by capture-upload, or
        # the original on a fallback) — recorded before IngestJob normalizes it,
        # so the client-side downscale is measurable (#556). IngestJob stamps
        # optimized_at, keeping the images:optimize backfill off freshly-captured
        # media regardless.
        original_byte_size: raw_byte_size
      )
      Success(media)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end
  end
end
