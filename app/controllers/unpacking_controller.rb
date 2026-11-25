# frozen_string_literal: true

# E3 — Unpacking Mode. The destination-side working surface for a single box:
# a checklist of in-box items with quick remove/restore, a live remaining count,
# and "mark box unpacked" (which cascades the rest to removed). When the box is
# already `unpacked` it renders the celebration. Runs inside an Organization
# tenant schema and is scoped to one Move. Thin: authorize, call the action,
# pattern-match, render.
class UnpackingController < MoveScopedController
  include BoxGridItems

  before_action :set_box
  before_action :ensure_unpacking_surface, only: :show
  before_action :set_item, only: %i[remove restore]
  before_action :set_media, only: :remove_photo
  before_action :require_writable_move!, only: %i[remove restore remove_photo complete reopen]
  before_action :require_active_checklist, only: %i[remove restore remove_photo]

  # GET /moves/:move_id/boxes/:box_id/unpacking

  #: () -> untyped
  def show
    editable = editable_move?
    return render(Views::Unpacking::Celebration.new(move: @move, box: @box, editable:)) if @box.unpacked?

    items = authorized_scope(@box.items)
    render Views::Unpacking::Checklist.new(
      move: @move, box: @box,
      remaining: items.in_box.ordered, unpacked: items.removed.ordered, editable:
    )
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/items/:item_id/remove
  # Tapping a remaining item marks it removed and moves it to the unpacked
  # section. Streams the surgical DOM updates (no reload) — the source row out,
  # the destination section + progress refreshed; HTML clients still redirect.
  # No toast: the checklist is a rapid tap-loop, so a toast per tap would spam.

  #: () -> untyped
  def remove
    # Items::Unpack owns the pair: MarkRemoved + the last-item auto-complete
    # (#755/#756 — the lifecycle rule lives in the action, not per adapter).
    result = Items::Unpack.new.call(item: @item, actor: current_user)
    return redirect_to_current_phase unless box_still_unpacking?

    case result
    in Dry::Monads::Success(_)
      respond_to_removed
    in Dry::Monads::Failure(_)
      # Nothing was removed (e.g. a concurrent change the action's own guard
      # caught, #729): re-render the real state with an alert instead of
      # success streams.
      respond_to_toggle_failure(t("unpacking.flash.remove_failed", name: @item.name)) do
        box_origin? ? box_streams : checklist_streams
      end
    end
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/items/:item_id/restore

  #: () -> untyped
  def restore
    result = Items::RestoreToBox.new.call(item: @item, actor: current_user)
    return redirect_to_current_phase unless box_still_unpacking?

    case result
    in Dry::Monads::Success(_)
      return respond_from_box if box_origin?

      respond_with_streams(move_item_streams(from: :unpacked, to: :remaining),
                           redirect: move_box_unpacking_path(@move, @box))
    in Dry::Monads::Failure(_)
      redirect_to move_box_unpacking_path(@move, @box), alert: t("unpacking.not_available")
    end
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/photos/:media_id/remove
  # B1's photo-level "Unpack photo" (#727): marks all the photo's still-in-box
  # items removed in one tap. Always box-origin — the control only exists on
  # the box detail grid.

  #: () -> untyped
  def remove_photo
    # MarkPhotoRemoved owns its completion (the bulk counterpart of
    # Items::Unpack); unpacking the last photo redirects like the last chip.
    result = Items::MarkPhotoRemoved.new.call(box: @box, media: @media, actor: current_user)
    return redirect_to_current_phase unless box_still_unpacking?

    case result
    in Dry::Monads::Success(removal)
      return respond_to_photo_moved if removal[:photo_moved]

      respond_with_streams([contents_header_stream, review_badge_stream, photo_card_stream(@media)],
                           redirect: move_box_path(@move, @box))
    in Dry::Monads::Failure(:not_found)
      # The photo left this box (a concurrent Photos::Move) after set_media:
      # drop its card and refresh the counts it no longer contributes to.
      respond_to_toggle_failure(t("unpacking.flash.photo_gone")) do
        [contents_header_stream, review_badge_stream, photo_card_stream(@media)]
      end
    in Dry::Monads::Failure(_)
      # The bulk loop is best-effort (the action documents why): a failure
      # can follow some committed removals, so re-render the whole card from
      # the DB rather than assume nothing changed (#729).
      respond_to_toggle_failure(t("unpacking.flash.photo_remove_failed")) do
        [contents_header_stream, review_badge_stream, photo_card_stream(@media)]
      end
    end
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/complete — mark the box unpacked
  # (cascades every remaining in-box item to removed in one transaction).

  #: () -> untyped
  def complete
    flash_key, message =
      case Boxes::TransitionStatus.new.call(box: @box, to: "unpacked", actor: current_user)
      in Dry::Monads::Success(_) then %i[notice completed]
      in Dry::Monads::Failure(:not_found) then return redirect_to_deleted_box
      # Already unpacked (last item unpacked on another device, a find-list
      # Found, a double tap — #971): the outcome the user asked for is in
      # place, so it is a notice, not a failure. No second event fires.
      in Dry::Monads::Failure(:invalid_transition) if @box.reload.unpacked? then %i[notice already_unpacked]
      in Dry::Monads::Failure(_) then %i[alert failed]
      end
    redirect_to move_box_unpacking_path(@move, @box), flash: { flash_key => t("unpacking.flash.#{message}") }
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/reopen — celebration "Undo".
  # Reopens the box (unpacked -> unpacking); removed items are restored
  # individually on the checklist, never auto-restored here.

  #: () -> untyped
  def reopen
    result = Boxes::TransitionStatus.new.call(box: @box, to: "unpacking", actor: current_user)
    result.failure? && result.failure == :not_found ? redirect_to_deleted_box : redirect_to(move_box_unpacking_path(@move, @box))
  end

  private

  # The box was deleted by another member after this request loaded it
  # (#980): its checklist is gone, so land on the boxes home instead.

  #: () -> untyped
  def redirect_to_deleted_box = redirect_to(move_boxes_path(@move), alert: t("unpacking.flash.box_deleted"), status: :see_other)

  #: () -> untyped
  def respond_to_removed
    return respond_from_box if box_origin?

    respond_with_streams(move_item_streams(from: :remaining, to: :unpacked),
                         redirect: move_box_unpacking_path(@move, @box))
  end

  # A refused toggle re-renders the affected regions from the DB (the
  # control snaps back to the real state) and explains itself with an alert
  # toast; 422 so the failure shows on the wire (Turbo renders stream bodies
  # whatever the status). Streams are built lazily — only on the Turbo path.
  # The HTML fallback redirects to the surface the request came from.

  #: (String message) { () -> Array[untyped] } -> untyped
  def respond_to_toggle_failure(message, &streams)
    # remove_photo is always box-origin (the control only exists on the grid).
    on_box = box_origin? || action_name == "remove_photo"
    redirect = on_box ? move_box_path(@move, @box) : move_box_unpacking_path(@move, @box)
    respond_with_streams(streams, redirect: redirect, toast: true, status: :unprocessable_content) do
      [:alert, message]
    end
  end

  # The checklist's real state after a refused remove: progress + both
  # sections, morphed so the tapped row (still in Remaining) keeps focus and
  # the page keeps its scroll position (UX rule 5).

  #: () -> Array[untyped]
  def checklist_streams
    editable = editable_move?
    remaining = ordered_items(:remaining)
    unpacked = ordered_items(:unpacked)
    [
      progress_stream(remaining_count: remaining.size, total: remaining.size + unpacked.size, method: :morph),
      section_stream(:remaining, remaining, editable, method: :morph),
      section_stream(:unpacked, unpacked, editable, method: :morph)
    ]
  end

  # Every toggle response, success or failure, first follows the box's
  # REALITY after the action ran (#877, Codex #886 R2). A box that left
  # `unpacking` (in practice: completed by this request, a concurrent one,
  # or a photo move that emptied it) gets a full navigation: the celebration
  # or the unpacked box summary are page-level changes no region stream
  # expresses. The reality, not whether THIS request won the completion race
  # (#756 P2): the loser of two concurrent last-item removals gets
  # completed_box nil, yet its streams would render an active surface for a
  # terminal box. Reload: the action ran on its own box object and a
  # concurrent writer may have committed since set_box, so every stream
  # renders from this post-action read, never the pre-action @box.

  #: () -> bool
  def box_still_unpacking? = @box.reload.unpacking?

  # The box left the checklist phase (in practice: it was marked unpacked,
  # by this request or a concurrent one). The grid lands on the box summary
  # with a toast; the checklist on the unpacking page, which renders the
  # celebration (or bounces an earlier phase to the box itself).

  #: () -> untyped
  def redirect_to_current_phase
    return redirect_to(move_box_unpacking_path(@move, @box)) unless box_origin? || action_name == "remove_photo"

    notice = @box.unpacked? ? t("unpacking.flash.completed") : t("unpacking.not_available")
    redirect_to move_box_path(@move, @box), notice: notice
  end

  # The photo left this box mid-loop (a concurrent Photos::Move, #877): the
  # items unpacked before it moved stay here, unpacked; the rest went with it.
  # Its card gives way to those left-behind items, and a notice says where the
  # rest went, rather than redraw a photo this box no longer holds. A partial
  # success, so 200.

  #: () -> untyped
  def respond_to_photo_moved
    respond_with_streams([contents_header_stream, review_badge_stream, photo_card_stream(@media)],
                         redirect: move_box_path(@move, @box), toast: true) do
      [:notice, t("unpacking.flash.photo_moved")]
    end
  end

  # The surgical Turbo Stream array for moving an item between the two checklist
  # sections (remove: remaining→unpacked, restore: unpacked→remaining). Symmetric:
  #   1. drop the tapped row from its source section,
  #   2. refresh the progress card (count + bar),
  #   3. re-render the destination section so the item lands at its sorted
  #      position (and the unpacked section reveals itself on the first item),
  #   4. only when the source section empties, re-render it too (remaining →
  #      all-clear empty state; unpacked → hidden). While it still has rows the
  #      per-row remove in step 1 is enough — the rest of the list is untouched.

  #: (from: Symbol, to: Symbol) -> Array[untyped]
  def move_item_streams(from:, to:)
    editable = editable_move?
    # Only the destination section is re-rendered, so only it needs its rows (with
    # categories) loaded; the source is just counted in SQL (no eager-load of a
    # list we won't render). When the source empties we render it with no rows.
    destination = ordered_items(to)
    source_count = items_scope(from).count #: Integer
    remaining_count = to == :remaining ? destination.size : source_count
    total = destination.size + source_count

    streams = [
      turbo_stream.remove(Components::Unpacking::ItemRow.dom_id(@item, from)),
      progress_stream(remaining_count: remaining_count, total: total),
      section_stream(to, destination, editable)
    ]
    streams << section_stream(from, [], editable) if source_count.zero?
    streams
  end

  #: (Symbol variant) -> untyped
  def items_scope(variant)
    scope = authorized_scope(@box.items)
    variant == :remaining ? scope.in_box : scope.removed
  end

  #: (Symbol variant) -> Array[untyped]
  def ordered_items(variant)
    items_scope(variant).ordered.to_a
  end

  #: (remaining_count: Integer, total: Integer, ?method: Symbol?) -> untyped
  def progress_stream(remaining_count:, total:, method: nil)
    turbo_stream.replace(
      Components::Unpacking::ProgressCard::ID,
      view_context.render(Components::Unpacking::ProgressCard.new(remaining_count:, total:)),
      method: method
    )
  end

  #: (Symbol variant, Array[untyped] items, untyped editable, ?method: Symbol?) -> untyped
  def section_stream(variant, items, editable, method: nil)
    component, id =
      if variant == :remaining
        [Components::Unpacking::RemainingSection.new(remaining: items, move: @move, box: @box, editable:),
         Components::Unpacking::RemainingSection::ID]
      else
        [Components::Unpacking::UnpackedSection.new(unpacked: items, move: @move, box: @box, editable:),
         Components::Unpacking::UnpackedSection::ID]
      end
    turbo_stream.replace(id, view_context.render(component), method: method)
  end

  # --- B1 box-detail origin (#727) -----------------------------------------
  # The grid's toggles send origin=box; the response then re-renders the
  # affected contents-grid card + the header count in place instead of the
  # checklist sections, and the HTML fallback returns to the box detail.

  #: () -> bool
  def box_origin? = params[:origin] == "box"

  #: () -> untyped
  def respond_from_box
    respond_with_streams(box_streams, redirect: move_box_path(@move, @box))
  end

  #: () -> Array[untyped]
  def box_streams
    [contents_header_stream, review_badge_stream, *grid_card_streams]
  end

  # The toggled item's grid card, from a post-action read (#877): the item
  # may have been unpacked, restored or moved out by a concurrent writer since
  # set_item, so @item's in-memory state is never rendered. A photo still in
  # this box redraws its photo card. Otherwise the server can't tell which
  # card the page holds, so both are addressed (Turbo ignores a missing
  # target): the departed photo's card, then the item's own card — redrawn
  # if the item is still here, dropped if it left the box.

  #: () -> Array[untyped]
  def grid_card_streams
    item = authorized_scope(@box.items).find_by(id: @item.id)
    media = fresh_media((item || @item).source_media_id)
    return [photo_card_stream(media)] if media

    own = item ? item_card_stream(item) : turbo_stream.remove(Components::Boxes::ItemCard.dom_id(@item))
    @item.source_media_id ? [departed_photo_stream(@item.source_media_id), own] : [own]
  end

  # The grid's photo-card membership (ready, not generated, kept), read now.

  #: (untyped id) -> untyped
  def fresh_media(id) = id && @box.media.ready.not_generated.find_by(id: id)

  # Item.unreviewed counts in-box items only, so toggling an unreviewed item's
  # presence changes the badge (Codex #728). Turbo ignores the replace when the
  # box has no walkable photo (the badge simply isn't in the DOM).

  #: () -> untyped
  def review_badge_stream
    turbo_stream.replace(
      Components::BoxReviewBadge::ID,
      view_context.render(Components::BoxReviewBadge.new(
                            move: @move, box: @box,
                            pending_count: authorized_scope(@box.items).unreviewed.count
                          ))
    )
  end

  #: () -> untyped
  def contents_header_stream
    scope = authorized_scope(@box.items)
    turbo_stream.replace(
      Components::Boxes::ContentsHeader::ID,
      view_context.render(Components::Boxes::ContentsHeader.new(
                            total: scope.count, unpacked: scope.removed.count
                          ))
    )
  end

  # Both card streams morph instead of replacing (idiomorph): a keyboard/AT
  # user's focus stays on the toggled chip — the node is attribute-updated in
  # place, not torn out (UX rule 5; Codex #728).

  # Re-reads the photo first: one that left this box (or was discarded)
  # since it was loaded is dropped from the grid, never redrawn (#877).

  #: (untyped loaded) -> untyped
  def photo_card_stream(loaded)
    media = fresh_media(loaded.id)
    return departed_photo_stream(loaded.id) if media.nil?

    items = authorized_scope(@box.items).where(source_media_id: media.id).order(:created_at, :id).to_a
    turbo_stream.replace(
      Components::Boxes::PhotoCard.dom_id(media),
      view_context.render(Components::Boxes::PhotoCard.new(
                            move: @move, box: @box, media: media, items: items,
                            # Review membership is presence-agnostic: the photo produced
                            # items, so its tile keeps linking to the review walk.
                            reviewable: @box.items.exists?(source_media_id: media.id),
                            # Move-wide, matching BoxesController#unpacked_media_ids —
                            # a sibling moved to another box keeps the badge withheld.
                            unpacked: @move.items.in_box.where(source_media_id: media.id).none?,
                            unpacking: @box.unpacking?, interactive: editable_move?
                          )),
      method: :morph
    )
  end

  # A photo that left this box (Codex #886): Photos::Move takes only its
  # in-box items, so the ones already unpacked stay here — and with their
  # photo gone, a full grid render shows them as standalone cards. The photo
  # card is removed and, when items stayed behind, the standalone region is
  # redrawn in full-render order so they land at their sorted place (#889).
  # One SafeBuffer, so the callers still get a single stream.

  #: (untyped media_id) -> untyped
  def departed_photo_stream(media_id)
    remove = turbo_stream.remove(Components::Boxes::PhotoCard.dom_id_for(media_id))
    return remove unless authorized_scope(@box.items).exists?(source_media_id: media_id)

    cards = view_context.safe_join(standalone_grid_items.map { |item| view_context.render(item_card(item)) })
    view_context.safe_join([remove, turbo_stream.update(Components::Boxes::ContentsGrid::STANDALONE_ID, cards)])
  end

  #: (untyped item) -> untyped
  def item_card_stream(item)
    turbo_stream.replace(Components::Boxes::ItemCard.dom_id(item), view_context.render(item_card(item)),
                         method: :morph)
  end

  #: (untyped item) -> untyped
  def item_card(item)
    Components::Boxes::ItemCard.new(item: item, move: @move, image_ready: @move.image_generation_ready?,
                                    unpacking: @box.unpacking? && editable_move?)
  end

  #: () -> untyped
  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Mirrors the contents grid's photo-card membership (ready, not generated) so
  # a generated/ingesting media id can never be bulk-unpacked.

  #: () -> untyped
  def set_media
    @media = @box.media.ready.not_generated.find(params.expect(:media_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  #: () -> untyped
  def set_item
    @item = authorized_scope(@box.items).find(params.expect(:item_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # The unpacking surface only exists once a box reaches `unpacking`; earlier
  # lifecycle states have no checklist. The celebration is shown once `unpacked`.
  # Bounce back to the box detail for any other state.

  #: () -> untyped
  def ensure_unpacking_surface
    return if @box.unpacking? || @box.unpacked?

    redirect_to move_box_path(@move, @box), alert: t("unpacking.not_available")
  end

  # Per-item remove/restore only make sense while the checklist is active
  # (status `unpacking`). On an `unpacked` box the celebration is showing, so
  # toggling an item back in_box would leave an inconsistent "done" box; on
  # earlier states there is no checklist at all. Reopen first to edit items.

  #: () -> untyped
  def require_active_checklist
    return if @box.unpacking?

    redirect_to move_box_unpacking_path(@move, @box), alert: t("unpacking.not_available")
  end

  # Archived-Move redirect target (require_writable_move!) — back to the
  # (read-only) unpacking checklist rather than the box.

  #: () -> String
  def read_only_redirect_path
    move_box_unpacking_path(@move, @box)
  end
end
