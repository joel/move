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
  def show
    render Views::Captures::Show.new(move: @move, box: @box, media: session_media)
  end

  # POST /moves/:move_id/boxes/:box_id/capture
  def create
    result = Captures::Create.new.call(box: @box, file: params[:file], captured_by: current_user)

    case result
    in Dry::Monads::Success(_media)
      redirect_to move_box_capture_path(@move, @box), notice: t(".captured")
    in Dry::Monads::Failure(reason)
      redirect_to move_box_capture_path(@move, @box), alert: capture_error(reason)
    end
  end

  # GET /moves/:move_id/boxes/:box_id/capture/session — polled fragment.
  # NB: not named `session` — that collides with ActionController#session.
  def session_panel
    render Views::Captures::SessionPanel.new(box: @box, media: session_media), layout: false
  end

  # POST /moves/:move_id/boxes/:box_id/capture/retry — new run for a failed media.
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

  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Capture into a sealed/closed box is blocked until it is unsealed (Domain §5.2).
  def require_capturable!
    return if @box.capturable?

    redirect_to move_box_path(@move, @box), alert: t("captures.sealed")
  end

  def session_media
    @box.media.includes(:recognition_runs, image_attachment: :blob).recent_first.limit(20)
  end

  def capture_error(reason)
    case reason
    when :no_file then t("captures.errors.no_file")
    when :not_capturable then t("captures.sealed")
    # Surface validation messages (e.g. an unsupported image format) so the user
    # gets actionable guidance instead of the generic "try again" fallback.
    when ActiveModel::Errors then reason.full_messages.to_sentence.presence || t("captures.errors.failed")
    else t("captures.errors.failed")
    end
  end

  # Archived-Move redirect target (require_writable_move!) — back to the box.
  def read_only_redirect_path
    move_box_path(@move, @box)
  end
end
