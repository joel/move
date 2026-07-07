# frozen_string_literal: true

# B2 — Capture image. Per-box capture surface: upload an image (online-only),
# which queues a recognition run; the session panel polls for live state. Capture
# into a sealed box is blocked (Domain §5.2). Thin: guard, call the action, render.
class CapturesController < MoveScopedController
  before_action :set_box
  before_action :require_writable_move!
  # Capture is blocked on a sealed box, but a pre-seal run can still be retried.
  before_action :require_capturable!, only: %i[show create direct_upload]

  # GET /moves/:move_id/boxes/:box_id/capture

  #: () -> untyped
  def show
    content = Captures::SessionContent.new(@box)
    render Views::Captures::Show.new(
      move: @move, box: @box, media: content.media, items_by_media: content.items_by_media
    )
  end

  # POST /moves/:move_id/boxes/:box_id/capture

  #: () -> untyped
  def create
    result = Captures::StartIngest.new.call(
      box: @box, file: params[:file], signed_id: params[:signed_id], captured_by: current_user
    )

    case result
    in Dry::Monads::Success(_media)
      # Async ingest (#545): the row + IngestJob exist, so answer immediately —
      # replace the panel with the pending placeholder tile (Turbo form) rather
      # than redirecting + re-rendering. The tile fills in over ActionCable as
      # ingest → recognition advance.
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            Views::Captures::SessionPanel::ID,
            view_context.render(Captures::SessionContent.new(@box).panel)
          )
        end
        format.html { redirect_to move_box_capture_path(@move, @box), notice: t(".captured") }
      end
    in Dry::Monads::Failure(reason)
      redirect_to move_box_capture_path(@move, @box), alert: capture_error(reason)
    end
  end

  # POST /moves/:move_id/boxes/:box_id/capture/direct_upload
  #
  # Direct-upload presign (#572). Reached only from the browser's @rails/activestorage
  # DirectUpload before it PUTs straight to R2. Reuses the capture guards
  # (membership + writable + capturable) so an unauthenticated or non-member request
  # can never mint a presigned URL. Validates the client-declared size/type up front
  # (the real content sniff + EXIF/GPS strip is still done server-side by
  # ImageNormalizer in IngestJob), and returns a Move-scoped signed_id so the blob
  # can only be attached to this Move.

  #: () -> untyped
  def direct_upload
    return head :not_found unless Rails.application.config.x.direct_upload_enabled

    blob_params = params.expect(blob: %i[filename byte_size checksum content_type])
    byte_size = blob_params[:byte_size].to_i
    return head :content_too_large unless byte_size.positive? && byte_size <= Media::MAX_IMAGE_BYTES

    content_type = blob_params[:content_type].to_s
    return head :unsupported_media_type unless content_type.start_with?("image/") && content_type != "image/svg+xml"

    # The R2 (S3) service builds a presigned S3 URL that needs no Rails host, but the
    # dev/test Disk service builds a Rails route URL that does — set the request host
    # so the presign works under every service (mirrors ActiveStorage's own controller).
    ActiveStorage::Current.url_options = { protocol: request.protocol, host: request.host, port: request.optional_port }

    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: blob_params[:filename], byte_size: byte_size,
      checksum: blob_params[:checksum], content_type: content_type
    )
    render json: direct_upload_response(blob)
  end

  # POST /moves/:move_id/boxes/:box_id/capture/retry — new run for a failed media.

  #: () -> untyped
  def retry_recognition
    media = @box.media.find(params.expect(:media_id))
    result = RecognitionRuns::Retry.new.call(run: media.recognition_runs.order(created_at: :desc).first)
    # Only the latest *failed* run is retryable; a no-op (e.g. replayed POST)
    # redirects quietly without queuing a duplicate run.
    notice = (t(".retried") if result.success?)
    redirect_to move_box_capture_path(@move, @box), notice: notice
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  #: () -> untyped
  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Capture into a sealed/closed box is blocked until it is unsealed (Domain §5.2).

  #: () -> untyped
  def require_capturable!
    return if @box.capturable?

    redirect_to move_box_path(@move, @box), alert: t("captures.sealed")
  end

  #: (untyped reason) -> untyped
  def capture_error(reason)
    case reason
    when :no_file then t("captures.errors.no_file")
    when :not_capturable then t("captures.sealed")
    when :unsupported_image then t("captures.errors.unsupported_image")
    when :image_too_large then t("captures.errors.image_too_large", max: Media::MAX_IMAGE_BYTES_LABEL)
    # Surface validation messages (e.g. an unsupported image format) so the user
    # gets actionable guidance instead of the generic "try again" fallback.
    when ActiveModel::Errors then reason.full_messages.to_sentence.presence || t("captures.errors.failed")
    else t("captures.errors.failed")
    end
  end

  # The @rails/activestorage DirectUpload response shape: the blob attrs + the
  # presigned PUT (url + headers) it uploads with, plus a Move-scoped signed_id (NOT
  # the default global one) that StartIngest verifies against this Move.

  #: (untyped blob) -> Hash[untyped, untyped]
  def direct_upload_response(blob)
    blob.as_json(root: false).merge(
      "signed_id" => blob.signed_id(purpose: Captures::StartIngest.signed_id_purpose(@move)),
      "direct_upload" => {
        "url" => blob.service_url_for_direct_upload,
        "headers" => blob.service_headers_for_direct_upload
      }
    )
  end

  # Archived-Move redirect target (require_writable_move!) — back to the box.

  #: () -> String
  def read_only_redirect_path
    move_box_path(@move, @box)
  end
end
