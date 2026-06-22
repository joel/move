# frozen_string_literal: true

# C2 — Per-photo review. Walks a box's photos one screen at a time; each screen
# lists every item detected in that photo as an editable field. Opening a photo
# marks its still-unreviewed items reviewed (Reviews::MarkPhotoReviewed). Items
# are edited inline (rename auto-saves on blur), removed (×), or added by hand;
# "Next Photo" only navigates. Runs inside an Organization tenant schema. Thin:
# authorize, call the action, render/redirect.
class ReviewsController < MoveScopedController
  before_action :set_box
  before_action :set_media, only: %i[photo rename_item remove_item add_item move_photo]
  before_action :set_item, only: %i[rename_item remove_item]
  before_action :require_writable_move!, only: %i[rename_item remove_item add_item move_photo]

  # GET /moves/:move_id/boxes/:box_id/review
  # Enter at the first photo that still has *unreviewed* items (resuming a
  # partially-reviewed box must not land on an already-confirmed photo); fall
  # back to the first photo, then to the box when there's nothing at all.
  def index
    media = first_unreviewed_media || review_media.first
    return redirect_to(move_box_path(@move, @box), notice: t("reviews.flash.nothing")) unless media

    redirect_to move_box_review_photo_path(@move, @box, media)
  end

  # GET /moves/:move_id/boxes/:box_id/review/photo/:media_id
  def photo
    # "Reviewed when its photo is shown" — only an editor on a writable Move
    # mutates (viewers / archived Moves see a read-only screen). This is a GET-side
    # effect, so every link that reaches a review photo disables Turbo prefetch
    # (`data-turbo-prefetch="false"` on the box pending badge and the "Next Photo"
    # link) — otherwise hovering them would confirm a photo before it is opened.
    Reviews::MarkPhotoReviewed.new.call(media: @media, actor: current_user) if editable_move?

    walk = review_media
    render Views::Reviews::Photo.new(
      move: @move, box: @box, media: @media, items: photo_items(@media),
      position: position_of(@media, walk), total: walk.size,
      next_media: next_after(@media, walk), editable: editable_move?,
      move_boxes: other_boxes
    )
  end

  # PATCH .../review/photo/:media_id/items/:id/rename — live auto-save (blur).
  # Name-only; 204 on success (the inline editor stays put), 422 on a rejected
  # name so the client can revert instead of showing a phantom save (#147).
  def rename_item
    # Pass the raw scalar (not params.expect, which 400s on a blank value) so a
    # rejected name flows through Items::Rename to a consistent 422.
    case Items::Rename.new.call(item: @item, name: params[:name].to_s, editor: current_user)
    in Dry::Monads::Success(_)
      head :no_content
    in Dry::Monads::Failure(_)
      head :unprocessable_content
    end
  end

  # PATCH .../review/photo/:media_id/items/:id/remove — drop a wrong detection.
  def remove_item
    # The review walk removes a mis-detected item *during packing* — a distinct use
    # case from destination-side unpacking, so it bypasses MarkRemoved's phase guard.
    Items::MarkRemoved.new.call(item: @item, actor: current_user, allow_any_phase: true)
    redirect_to move_box_review_photo_path(@move, @box, @media)
  end

  # POST .../review/photo/:media_id/items — add a missed item to this photo.
  def add_item
    result = Items::CreateManual.new.call(
      box: @box, params: { name: params.dig(:item, :name) }, creator: current_user, source_media: @media
    )

    case result
    in Dry::Monads::Success(_item)
      redirect_to move_box_review_photo_path(@move, @box, @media)
    in Dry::Monads::Failure(_)
      redirect_to move_box_review_photo_path(@move, @box, @media), alert: t("reviews.flash.add_failed")
    end
  end

  # PATCH .../review/photo/:media_id/move — move this photo (and its co-located
  # items) to another box in the same Move (#317). On success the photo now lives
  # in the target box, so redirect there (its review URL under @box would 404).
  def move_photo
    target = @move.boxes.find_by(id: params[:target_box_id])

    case Photos::Move.new.call(media: @media, target_box: target, mover: current_user)
    in Dry::Monads::Success(_media)
      redirect_to move_box_path(@move, target), notice: t("reviews.flash.photo_moved", number: target.number)
    in Dry::Monads::Failure(reason)
      redirect_to move_box_review_photo_path(@move, @box, @media), alert: move_photo_error(reason)
    end
  end

  private

  def move_photo_error(reason)
    key = %i[box_missing same_box cross_move move_archived].include?(reason) ? reason : :failed
    t("reviews.flash.move_photo_errors.#{key}")
  end

  # Boxes (other than this one) the photo can be moved to, numerically ordered — a
  # string `number` would sort lexically ("10" before "9"), the #283 trap.
  def other_boxes
    authorized_scope(@move.boxes).where.not(id: @box.id).order(Arel.sql("number::bigint"))
  end

  # Every photo in this box that ever produced an item (in-box OR removed), in
  # capture order — the stable walk for position / total / next. It deliberately
  # does NOT filter on in_box: removing the last detection from the current photo
  # must not drop it from the walk (that would make `next_after` return nil and
  # let the reviewer skip the remaining photos via "Finish"). The per-photo list
  # itself is still in-box only (see `photo_items`).
  def review_media
    @review_media ||= begin
      ids = @box.items.where.not(source_media_id: nil).distinct.pluck(:source_media_id)
      @box.media.where(id: ids).order(:captured_at, :created_at).to_a
    end
  end

  # The first photo (in walk order) that still holds an unreviewed item — where
  # the entry should drop the user when resuming a partially-reviewed box.
  def first_unreviewed_media
    ids = @box.items.in_box.where(review_state: %w[pending_review needs_correction])
              .where.not(source_media_id: nil).distinct.pluck(:source_media_id)
    return nil if ids.empty?

    review_media.find { |m| ids.include?(m.id) }
  end

  # Every in-box item detected in (or hand-added to) this photo, in detection
  # order. Manual review-time additions carry source_media so they join the list.
  def photo_items(media)
    @box.items.in_box.where(source_media_id: media.id).order(:created_at)
  end

  def position_of(media, walk)
    (walk.index { |m| m.id == media.id } || 0) + 1
  end

  def next_after(media, walk)
    idx = walk.index { |m| m.id == media.id }
    idx && walk[idx + 1]
  end

  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Media / items are reached through the already-authorized box, so box scoping
  # is the tenant boundary (no separate media policy needed).
  def set_media
    @media = @box.media.find(params.expect(:media_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def set_item
    @item = @box.items.find(params.expect(:id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Archived-Move redirect target (require_writable_move!) — back to the box.
  def read_only_redirect_path
    move_box_path(@move, @box)
  end
end
