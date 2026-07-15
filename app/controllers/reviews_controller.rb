# frozen_string_literal: true

# C2 — Per-photo review. Walks a box's photos one screen at a time; each screen
# lists every item detected in that photo as an editable field. Opening a photo
# marks its still-unreviewed items reviewed (Reviews::MarkPhotoReviewed). Items
# are edited inline (rename auto-saves on blur), removed (×), or added by hand;
# "Next Photo" only navigates. Runs inside an Organization tenant schema. Thin:
# authorize, call the action, render/redirect.
class ReviewsController < MoveScopedController
  before_action :set_box
  before_action :set_media, only: %i[photo rename_item remove_item add_item move_photo delete_photo retake_photo]
  before_action :set_item, only: %i[rename_item remove_item]
  before_action :require_writable_move!,
                only: %i[rename_item remove_item add_item move_photo delete_photo retake_photo]

  # GET /moves/:move_id/boxes/:box_id/review
  # Enter at the first photo that still has *unreviewed* items (resuming a
  # partially-reviewed box must not land on an already-confirmed photo); fall
  # back to the first photo, then to the box when there's nothing at all.

  #: () -> untyped
  def index
    media = first_unreviewed_media || review_media.first
    return redirect_to(move_box_path(@move, @box), notice: t("reviews.flash.nothing")) unless media

    redirect_to move_box_review_photo_path(@move, @box, media)
  end

  # GET /moves/:move_id/boxes/:box_id/review/photo/:media_id

  #: () -> untyped
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

  #: () -> untyped
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
  # Streams the row out (no reload); flips to the empty state on the last item.
  # No toast — the row vanishing is the feedback, and corrections come in bursts.

  #: () -> untyped
  def remove_item
    # The review walk removes a mis-detected item *during packing* — a distinct use
    # case from destination-side unpacking, so it bypasses MarkRemoved's phase guard.
    Items::MarkRemoved.new.call(item: @item, actor: current_user, allow_any_phase: true)
    items = photo_items(@media).to_a
    streams = [turbo_stream.remove(Components::Reviews::ItemRow.dom_id(@item))]
    streams << review_list_stream(items) if items.empty?
    respond_with_streams(streams, redirect: move_box_review_photo_path(@move, @box, @media))
  end

  # POST .../review/photo/:media_id/items — add a missed item to this photo. Streams
  # the new row in (highlighted + scrolled into view) with a confirmation toast
  # (UX rule #1); HTML clients still redirect.

  #: () -> untyped
  def add_item
    result = Items::CreateManual.new.call(
      box: @box, params: { name: params.dig(:item, :name) }, creator: current_user, source_media: @media
    )

    case result
    in Dry::Monads::Success(item)
      add_item_success(item)
    in Dry::Monads::Failure(_)
      # Non-2xx so the reset-form controller leaves the typed name intact for a retry.
      respond_with_streams([], redirect: move_box_review_photo_path(@move, @box, @media),
                               toast: true, status: :unprocessable_content) do
        [:alert, t("reviews.flash.add_failed")]
      end
    end
  end

  # PATCH .../review/photo/:media_id/move — move this photo (and its co-located
  # items) to another box in the same Move (#317). On success the photo now lives
  # in the target box, so redirect there (its review URL under @box would 404).

  #: () -> untyped
  def move_photo
    target = @move.boxes.find_by(id: params[:target_box_id])

    case Photos::Move.new.call(media: @media, target_box: target, mover: current_user)
    in Dry::Monads::Success(_media)
      redirect_to move_box_path(@move, target), notice: t("reviews.flash.photo_moved", number: target.number)
    in Dry::Monads::Failure(reason)
      redirect_to move_box_review_photo_path(@move, @box, @media), alert: move_photo_error(reason)
    end
  end

  # DELETE .../review/photo/:media_id — delete this photo and every item it
  # sourced (Photos::Delete, packing only, soft + cascading). The page's subject is
  # gone, so redirect to the box like the box/item delete flows.

  #: () -> untyped
  def delete_photo
    case Photos::Delete.new.call(media: @media, actor: current_user)
    in Dry::Monads::Success(_media)
      redirect_to move_box_path(@move, @box), notice: t("reviews.flash.photo_deleted")
    in Dry::Monads::Failure(:wrong_phase)
      redirect_to move_box_review_photo_path(@move, @box, @media), alert: t("reviews.flash.photo_delete_wrong_phase")
    in Dry::Monads::Failure(_)
      redirect_to move_box_review_photo_path(@move, @box, @media), alert: t("reviews.flash.photo_delete_failed")
    end
  end

  # POST .../review/photo/:media_id/retake — replace this photo's image (recover a
  # corrupt master or swap a bad shot); any phase, optional AI re-scan (#577).

  #: () -> untyped
  def retake_photo
    result = Captures::Retake.new.call(
      media: @media, actor: current_user, file: params[:file],
      rerun_recognition: ActiveModel::Type::Boolean.new.cast(params[:rerun_recognition])
    )

    case result
    in Dry::Monads::Success(_media)
      redirect_to move_box_review_photo_path(@move, @box, @media), notice: t("reviews.flash.photo_retaken")
    in Dry::Monads::Failure(reason)
      redirect_to move_box_review_photo_path(@move, @box, @media), alert: retake_error(reason)
    end
  end

  private

  #: (untyped reason) -> String
  def retake_error(reason)
    known = %i[no_file recognition_in_flight rescan_wrong_phase image_too_large unsupported_image]
    t("reviews.flash.retake_errors.#{known.include?(reason) ? reason : :failed}")
  end

  # Stream the new item in by replacing the whole list (highlighting the new row)
  # plus a toast. We always replace — never append — because the append target
  # (#review-item-rows) is absent on a client that loaded the photo empty, and the
  # post-create DB count can't tell us that client's DOM state (a concurrent add or
  # a race would make the count > 1 yet the rows container still wouldn't exist
  # here, so Turbo would silently drop an append). The stable list wrapper always
  # exists, so a replace is robust regardless of how the page was first rendered.

  #: (untyped item) -> untyped
  def add_item_success(item)
    items = photo_items(@media).to_a
    respond_with_streams([review_list_stream(items, highlight_id: item.id)],
                         redirect: move_box_review_photo_path(@move, @box, @media), toast: true) do
      [:notice, t("reviews.flash.item_added", name: item.name)]
    end
  end

  #: (Array[untyped] items, ?highlight_id: untyped) -> untyped
  def review_list_stream(items, highlight_id: nil)
    turbo_stream.replace(
      Components::Reviews::ItemList::ID,
      view_context.render(Components::Reviews::ItemList.new(
                            move: @move, box: @box, media: @media, items: items, editable: editable_move?, highlight_id: highlight_id
                          ))
    )
  end

  #: (untyped reason) -> String
  def move_photo_error(reason)
    key = %i[box_missing same_box cross_move move_archived].include?(reason) ? reason : :failed
    t("reviews.flash.move_photo_errors.#{key}")
  end

  # Boxes (other than this one) the photo can be moved to, numerically ordered — a
  # string `number` would sort lexically ("10" before "9"), the #283 trap.

  #: () -> untyped
  def other_boxes
    authorized_scope(@move.boxes).where.not(id: @box.id).order(Arel.sql("number::bigint"))
  end

  # Every photo in this box that ever produced an item (in-box OR removed), in
  # capture order — the stable walk for position / total / next. It deliberately
  # does NOT filter on in_box: removing the last detection from the current photo
  # must not drop it from the walk (that would make `next_after` return nil and
  # let the reviewer skip the remaining photos via "Finish"). The per-photo list
  # itself is still in-box only (see `photo_items`).

  #: () -> Array[untyped]
  def review_media
    @review_media ||= begin
      ids = @box.items.where.not(source_media_id: nil).distinct.pluck(:source_media_id)
      # not_generated: an AI-generated item image is not a recognised capture, so it
      # never enters the review walk (#416).
      @box.media.not_generated.where(id: ids).order(:captured_at, :created_at).to_a
    end
  end

  # The first photo (in walk order) that still holds an unreviewed item — where
  # the entry should drop the user when resuming a partially-reviewed box.

  #: () -> untyped
  def first_unreviewed_media
    ids = @box.items.unreviewed
              .where.not(source_media_id: nil).distinct.pluck(:source_media_id)
    return nil if ids.empty?

    review_media.find { |m| ids.include?(m.id) }
  end

  # Every in-box item detected in (or hand-added to) this photo, in detection
  # order. Manual review-time additions carry source_media so they join the list.

  #: (untyped media) -> untyped
  def photo_items(media)
    @box.items.in_box.where(source_media_id: media.id).order(:created_at)
  end

  #: (untyped media, Array[untyped] walk) -> Integer
  def position_of(media, walk)
    (walk.index { |m| m.id == media.id } || 0) + 1
  end

  #: (untyped media, Array[untyped] walk) -> untyped
  def next_after(media, walk)
    idx = walk.index { |m| m.id == media.id }
    idx && walk[idx + 1]
  end

  #: () -> untyped
  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Media / items are reached through the already-authorized box, so box scoping
  # is the tenant boundary (no separate media policy needed).

  #: () -> untyped
  def set_media
    @media = @box.media.find(params.expect(:media_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  #: () -> untyped
  def set_item
    @item = @box.items.find(params.expect(:id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Archived-Move redirect target (require_writable_move!) — back to the box.

  #: () -> String
  def read_only_redirect_path
    move_box_path(@move, @box)
  end
end
