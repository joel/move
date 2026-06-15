# frozen_string_literal: true

# Recovery for an orphaned photo — a Media whose recognition failed or found
# nothing, so no Item exists. The box gallery is the only persistent entry point
# (the capture session panel's Retry is transient). Thin: authorize through the
# box, then re-run recognition (reusing RecognitionRuns::Retry) or hand off to the
# manual add (B3). Runs inside an Organization tenant schema.
class RecoveriesController < MoveScopedController
  before_action :set_box
  before_action :set_media
  before_action :require_writable_move!, only: %i[retry]

  # GET /moves/:move_id/boxes/:box_id/recovery/photo/:media_id
  def show
    # A resolved photo (it now has an item) is no longer orphaned — send it to the
    # per-photo review walk instead of a dead recovery screen.
    return redirect_to(move_box_review_photo_path(@move, @box, @media)) if recovered?

    render Views::Recoveries::Show.new(
      move: @move, box: @box, media: @media, run: latest_run, editable: editable_move?
    )
  end

  # GET .../recovery/photo/:media_id/state — polled status fragment (recognition
  # poller) so a re-run's progress updates in place without a manual refresh.
  def state
    # layout: false — the recognition poller injects this straight into the panel
    # frame; without it each poll would nest the whole AppShell inside the card.
    render Views::Recoveries::State.new(
      move: @move, box: @box, media: @media, run: latest_run,
      editable: editable_move?, recovered: recovered?
    ), layout: false
  end

  # POST .../recovery/photo/:media_id/retry — re-run recognition on a failed photo.
  # RecognitionRuns::Retry guards failed-only + writable, so a stale double-submit
  # is a harmless no-op (replayable POST).
  def retry
    result = RecognitionRuns::Retry.new.call(run: latest_run)
    redirect_to move_box_recovery_photo_path(@move, @box, @media),
                notice: (t(".retried") if result.success?)
  end

  private

  def recovered?
    @box.items.exists?(source_media_id: @media.id)
  end

  def latest_run
    @latest_run ||= @media.recognition_runs.order(created_at: :desc).first
  end

  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Media is reached through the already-authorized box (box scoping is the tenant
  # boundary), mirroring ReviewsController#set_media.
  def set_media
    @media = @box.media.find(params.expect(:media_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Archived-Move redirect target (require_writable_move!) — back to the box.
  def read_only_redirect_path
    move_box_path(@move, @box)
  end
end
