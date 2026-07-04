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

  #: () -> untyped
  def show
    # A resolved photo (it now has an item) is no longer orphaned — send it to that
    # item, not a dead recovery screen.
    return redirect_to(recovered_redirect_path) if @media.sourced_item?
    # A photo whose recognition produced a result other than an item (e.g. a
    # conflict-only run — suggestions but no item, by the no-overwrite rule) is not
    # orphaned; offering manual add would recreate the avoided duplicate.
    return redirect_to(move_box_path(@move, @box)) unless @media.orphaned?

    render Views::Recoveries::Show.new(
      move: @move, box: @box, media: @media, run: latest_run, editable: editable_move?
    )
  end

  # GET .../recovery/photo/:media_id/state — polled status fragment (recognition
  # poller) so a re-run's progress updates in place without a manual refresh.

  #: () -> untyped
  def state
    # layout: false — the recognition poller injects this straight into the panel
    # frame; without it each poll would nest the whole AppShell inside the card.
    render Views::Recoveries::State.new(
      move: @move, box: @box, media: @media, run: latest_run,
      editable: editable_move?, recovered: @media.sourced_item?, orphaned: @media.orphaned?
    ), layout: false
  end

  # POST .../recovery/photo/:media_id/retry — re-run recognition on a failed photo.
  # RecognitionRuns::Retry guards failed-only + writable, so a stale double-submit
  # is a harmless no-op (replayable POST).

  #: () -> untyped
  def retry
    # The page may be stale: the photo could have been resolved (manual add) or
    # conflict-matched since it loaded, with the run still `failed`. Don't re-run
    # recognition on a no-longer-orphaned photo — bounce to #show, which redirects
    # to the item / box as appropriate.
    return redirect_to(move_box_recovery_photo_path(@move, @box, @media)) unless @media.orphaned?

    result = RecognitionRuns::Retry.new.call(run: latest_run)
    redirect_to move_box_recovery_photo_path(@move, @box, @media),
                notice: (t(".retried") if result.success?)
  end

  private

  # A recovered photo's item may live in another box (Items::Move), so the
  # original box's review walk (box-scoped) wouldn't contain it — sending there
  # renders an empty "Photo 1 of 0". Go to the item itself instead.

  #: () -> String
  def recovered_redirect_path
    item = @move.items.find_by(source_media_id: @media.id)
    item ? move_item_path(@move, item) : move_box_path(@move, @box)
  end

  #: () -> untyped
  def latest_run
    @latest_run ||= @media.recognition_runs.order(created_at: :desc).first
  end

  #: () -> untyped
  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Media is reached through the already-authorized box (box scoping is the tenant
  # boundary), mirroring ReviewsController#set_media.

  #: () -> untyped
  def set_media
    @media = @box.media.find(params.expect(:media_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Archived-Move redirect target (require_writable_move!) — back to the box.

  #: () -> String
  def read_only_redirect_path
    move_box_path(@move, @box)
  end
end
