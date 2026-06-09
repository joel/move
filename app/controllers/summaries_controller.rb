# frozen_string_literal: true

# F2 — Volume & weight summary. A read surface for any Move member showing total
# volume, optional total weight, a per-room breakdown, the box count, and honest
# missing-dimension warnings. The Metric/Imperial toggle persists Move#unit_system
# (editors only, never on an archived Move); storage stays canonical metric so the
# toggle changes display only (Technical Foundation §6.2). Thin: authorize → call
# Moves::VolumeSummary → render.
class SummariesController < MoveScopedController
  before_action { Current.nav_section = :summary }

  # GET /moves/:move_id/summary
  def show
    authorize! @move, to: :show?, with: MovePolicy

    result = Moves::VolumeSummary.new.call(move: @move, actor: current_user)

    case result
    in Dry::Monads::Success(summary)
      render Views::Summaries::Show.new(move: @move, summary: summary, editable: editable_units?)
    in Dry::Monads::Failure(_)
      redirect_to move_boxes_path(@move), alert: t(".error")
    end
  end

  # PATCH /moves/:move_id/summary/unit_system
  def update_unit_system
    authorize! @move, to: :edit_contents?, with: MovePolicy
    return redirect_to move_summary_path(@move), alert: t(".read_only") unless @move.writable?

    result = Moves::SetUnitSystem.new.call(
      move: @move, unit_system: params.dig(:move, :unit_system), actor: current_user
    )

    case result
    in Dry::Monads::Success(_move)
      redirect_to move_summary_path(@move), notice: t(".changed")
    in Dry::Monads::Failure(_)
      redirect_to move_summary_path(@move), alert: t(".invalid")
    end
  end

  private

  # The unit toggle is only shown to a user who could actually change it —
  # an editor (admin/contributor) on a writable Move. A viewer or an archived
  # Move sees the resolved unit system as plain text, never a control that would
  # 403 on submit.
  def editable_units?
    @move.writable? && allowed_to?(:edit_contents?, @move, with: MovePolicy)
  end
end
