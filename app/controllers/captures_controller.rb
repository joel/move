# frozen_string_literal: true

# B2 — Capture image. Per-box capture surface: upload an image (online-only),
# which queues a recognition run; the session panel polls for live state. Capture
# into a sealed box is blocked (Domain §5.2). Thin: guard, call the action, render.
class CapturesController < MoveScopedController
  before_action :set_box
  before_action :require_writable_move!
  # Capture is blocked on a sealed box, but a pre-seal run can still be retried.
  before_action :require_capturable!, only: %i[show create]

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
    result = Captures::StartIngest.new.call(box: @box, file: params[:file], captured_by: current_user)

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

  # Archived-Move redirect target (require_writable_move!) — back to the box.

  #: () -> String
  def read_only_redirect_path
    move_box_path(@move, @box)
  end
end
