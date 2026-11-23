# frozen_string_literal: true

# The responses for ReviewsController#move_photo (Photos::Move): the success
# redirect (#317/#838) and every failure, including losing the race to a
# concurrent delete or move (#874). Expects the including controller to set
# @move, @box and @media and to define queue_mode?/queue_query (ReviewsController).
# NB: concern modules are unchecked by Steep (Steepfile note); this module's
# surface is declared in sig/concerns.rbs like the other controller concerns.
module ReviewPhotoMoveResponses
  extend ActiveSupport::Concern

  private

  # The photo-move success response. In queue mode stay in the walk: the photo
  # now lives in the target box, so continue on its review URL there (re-opening
  # is idempotent) instead of ejecting the reviewer to the target box page
  # mid-queue. Moving the photo whose items were the last in-box items of an
  # unpacking box completes that SOURCE box (#838, Photos::Move); that happens
  # off-screen, so it surfaces with a LINKING toast to the source box (UX rule 1)
  # instead of the plain moved toast — built from the box's reality, as
  # ItemsController#moved_response does.

  def photo_moved_response(target, completed_source:)
    path = photo_landing_path(target)
    return redirect_to(path, notice: t("reviews.flash.photo_moved", number: target.number)) unless completed_source

    redirect_to path, notice: t("reviews.flash.photo_moved_box_unpacked", number: target.number, source: completed_source.number),
                      flash: { action_href: move_box_path(@move, completed_source), action_label: t("reviews.flash.view_box") }
  end

  # A concurrent request won the race against Photos::Move (#874): a delete
  # discarded the photo (or its box) while the move waited on the lock
  # (:not_found), or concurrent moves kept relocating it (:box_changed). Either
  # way the photo is no longer under @box, so the usual redirect back to its
  # review URL would 404. Decide from the photo's state NOW, not the reason: land
  # where it lives (the same page a successful move lands on), or, when it's
  # gone, on a page that still exists, and say what happened.

  def photo_move_lost_race
    current_box = @move.media.find_by(id: @media.id)&.box # kept scopes: nil once discarded
    return redirect_to(photo_gone_path, alert: move_photo_error(:photo_deleted)) unless current_box
    # Still in @box (an unexpected reason): its review URL resolves, keep the generic alert.
    return redirect_to(move_box_review_photo_path(@move, @box, @media, **queue_query), alert: move_photo_error(:failed)) if current_box.id == @box.id

    redirect_to photo_landing_path(current_box), alert: t("reviews.flash.move_photo_errors.moved_elsewhere", number: current_box.number)
  end

  # Where to land once the photo is gone: the queue page in queue mode, else
  # the box — or the box list when a concurrent box delete took the box with it.

  # Where the reviewer lands once the photo lives in `box`: its review URL there
  # in queue mode (stay in the walk), else that box's page.
  def photo_landing_path(box)
    queue_mode? ? move_box_review_photo_path(@move, box, @media, **queue_query) : move_box_path(@move, box)
  end

  def photo_gone_path
    return move_review_path(@move) if queue_mode?

    @move.boxes.exists?(@box.id) ? move_box_path(@move, @box) : move_boxes_path(@move)
  end

  def move_photo_error(reason)
    key = %i[box_missing same_box cross_move move_archived photo_deleted].include?(reason) ? reason : :failed
    t("reviews.flash.move_photo_errors.#{key}")
  end
end
