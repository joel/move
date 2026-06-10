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
  def show
    editable = editable_move?
    return render(Views::Unpacking::Celebration.new(move: @move, box: @box, editable:)) if @box.unpacked?

    items = authorized_scope(@box.items).includes(:category)
    render Views::Unpacking::Checklist.new(
      move: @move, box: @box,
      remaining: items.in_box.ordered, unpacked: items.removed.ordered, editable:
    )
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/items/:item_id/remove
  def remove
    Items::MarkRemoved.new.call(item: @item, actor: current_user)
    redirect_to move_box_unpacking_path(@move, @box)
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/items/:item_id/restore
  def restore
    Items::RestoreToBox.new.call(item: @item, actor: current_user)
    redirect_to move_box_unpacking_path(@move, @box)
  end

  # PATCH /moves/:move_id/boxes/:box_id/unpacking/complete — mark the box unpacked
  # (cascades every remaining in-box item to removed in one transaction).
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
  def reopen
    Boxes::TransitionStatus.new.call(box: @box, to: "unpacking", actor: current_user)
    redirect_to move_box_unpacking_path(@move, @box)
  end

  private

  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def set_item
    @item = authorized_scope(@box.items).find(params.expect(:item_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # The unpacking surface only exists once a box reaches `unpacking`; earlier
  # lifecycle states have no checklist. The celebration is shown once `unpacked`.
  # Bounce back to the box detail for any other state.
  def ensure_unpacking_surface
    return if @box.unpacking? || @box.unpacked?

    redirect_to move_box_path(@move, @box), alert: t("unpacking.not_available")
  end

  # Per-item remove/restore only make sense while the checklist is active
  # (status `unpacking`). On an `unpacked` box the celebration is showing, so
  # toggling an item back in_box would leave an inconsistent "done" box; on
  # earlier states there is no checklist at all. Reopen first to edit items.
  def require_active_checklist
    return if @box.unpacking?

    redirect_to move_box_unpacking_path(@move, @box), alert: t("unpacking.not_available")
  end

  # Archived Moves are read-only — no toggling items or completing/reopening.
  def require_writable_move!
    authorize_move_mutation!
    return if @move.writable?

    redirect_to move_box_unpacking_path(@move, @box), alert: t("unpacking.archived")
  end
end
