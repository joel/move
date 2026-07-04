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
  before_action :require_writable_move!, only: %i[remove restore complete reopen]
  before_action :require_active_checklist, only: %i[remove restore]

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
    Items::MarkRemoved.new.call(item: @item, actor: current_user)
    respond_with_streams(move_item_streams(from: :remaining, to: :unpacked),
                         redirect: move_box_unpacking_path(@move, @box))
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/items/:item_id/restore

  #: () -> untyped
  def restore
    Items::RestoreToBox.new.call(item: @item, actor: current_user)
    respond_with_streams(move_item_streams(from: :unpacked, to: :remaining),
                         redirect: move_box_unpacking_path(@move, @box))
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

  #: () -> untyped
  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
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
