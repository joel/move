# frozen_string_literal: true

# E3 — Unpacking Mode. The destination-side working surface for a single box:
# a checklist of in-box items with quick remove/restore, a live remaining count,
# and "mark box unpacked" (which cascades the rest to removed). When the box is
# already `unpacked` it renders the celebration. Runs inside an Organization
# tenant schema and is scoped to one Move. Thin: authorize, call the action,
# pattern-match, render.
class UnpackingController < MoveScopedController
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
    Items::Unpack.new.call(item: @item, actor: current_user)
    # The response is a full navigation when the box completed — the
    # celebration (checklist) or the unpacked box summary (grid origin) are
    # page-level changes no region stream expresses.
    if box_completed?
      return redirect_to(move_box_path(@move, @box), notice: t("unpacking.flash.completed")) if box_origin?

      return redirect_to(move_box_unpacking_path(@move, @box))
    end
    return respond_from_box if box_origin?

    respond_with_streams(move_item_streams(from: :remaining, to: :unpacked),
                         redirect: move_box_unpacking_path(@move, @box))
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/items/:item_id/restore

  #: () -> untyped
  def restore
    case Items::RestoreToBox.new.call(item: @item, actor: current_user)
    in Dry::Monads::Success(_)
      return respond_from_box if box_origin?

      respond_with_streams(move_item_streams(from: :unpacked, to: :remaining),
                           redirect: move_box_unpacking_path(@move, @box))
    in Dry::Monads::Failure(:box_unpacked)
      # The box completed between require_active_checklist and the box-locked
      # guard (#756 R3): nothing mutated — success streams would strip a row
      # the DB still holds. Land on the surface that shows the terminal state.
      redirect_to box_origin? ? move_box_path(@move, @box) : move_box_unpacking_path(@move, @box)
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
    Items::MarkPhotoRemoved.new.call(box: @box, media: @media, actor: current_user)
    return redirect_to(move_box_path(@move, @box), notice: t("unpacking.flash.completed")) if box_completed?

    respond_with_streams([contents_header_stream, review_badge_stream, photo_card_stream(@media)],
                         redirect: move_box_path(@move, @box))
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/complete — mark the box unpacked
  # (cascades every remaining in-box item to removed in one transaction).

  #: () -> untyped
  def complete
    result = Boxes::TransitionStatus.new.call(box: @box, to: "unpacked", actor: current_user)

    case result
    in Dry::Monads::Success(box)
      redirect_to move_box_unpacking_path(@move, box), notice: t("unpacking.flash.completed")
    in Dry::Monads::Failure(_reason)
      redirect_to move_box_unpacking_path(@move, @box), alert: t("unpacking.flash.failed")
    end
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/reopen — celebration "Undo".
  # Reopens the box (unpacked -> unpacking); removed items are restored
  # individually on the checklist, never auto-restored here.

  #: () -> untyped
  def reopen
    Boxes::TransitionStatus.new.call(box: @box, to: "unpacking", actor: current_user)
    redirect_to move_box_unpacking_path(@move, @box)
  end

  private

  # The response follows the box's REALITY after the unpack ran, not whether
  # THIS request won the completion race (#756 P2): the loser of two
  # concurrent last-item removals gets completed_box nil — the post-lock
  # re-read saw `unpacked` — but its checklist/grid streams would render an
  # active surface for a terminal box, so it must redirect just the same.
  # Reload: the action completed via @item.box, a different AR object.

  #: () -> bool
  def box_completed?
    @box.reload.unpacked?
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

  #: (remaining_count: Integer, total: Integer) -> untyped
  def progress_stream(remaining_count:, total:)
    turbo_stream.replace(
      Components::Unpacking::ProgressCard::ID,
      view_context.render(Components::Unpacking::ProgressCard.new(remaining_count:, total:))
    )
  end

  #: (Symbol variant, Array[untyped] items, untyped editable) -> untyped
  def section_stream(variant, items, editable)
    component, id =
      if variant == :remaining
        [Components::Unpacking::RemainingSection.new(remaining: items, move: @move, box: @box, editable:),
         Components::Unpacking::RemainingSection::ID]
      else
        [Components::Unpacking::UnpackedSection.new(unpacked: items, move: @move, box: @box, editable:),
         Components::Unpacking::UnpackedSection::ID]
      end
    turbo_stream.replace(id, view_context.render(component))
  end

  # --- B1 box-detail origin (#727) -----------------------------------------
  # The grid's toggles send origin=box; the response then re-renders the
  # affected contents-grid card + the header count in place instead of the
  # checklist sections, and the HTML fallback returns to the box detail.

  #: () -> bool
  def box_origin?
    params[:origin] == "box"
  end

  #: () -> untyped
  def respond_from_box
    media = @box.media.ready.not_generated.find_by(id: @item.source_media_id)
    streams = [contents_header_stream, review_badge_stream,
               media ? photo_card_stream(media) : item_card_stream]
    respond_with_streams(streams, redirect: move_box_path(@move, @box))
  end

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

  #: (untyped media) -> untyped
  def photo_card_stream(media)
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

  #: () -> untyped
  def item_card_stream
    turbo_stream.replace(
      Components::Boxes::ItemCard.dom_id(@item),
      view_context.render(Components::Boxes::ItemCard.new(
                            item: @item, move: @move, image_ready: @move.image_generation_ready?,
                            unpacking: @box.unpacking? && editable_move?
                          )),
      method: :morph
    )
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
