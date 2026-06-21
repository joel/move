# frozen_string_literal: true

# Phase 44 — Bulk box lifecycle steps. A Move-scoped, editor-only surface reached
# from the Menu that advances every box in a source state through one forward
# lifecycle step in a single click ("Seal all packing boxes", "Send all sealed
# boxes in transit", …). Thin: authorize → call Boxes::BulkTransition →
# pattern-match → redirect with a summary flash.
#
# Reads (`show`) and the mutation (`create`) both require an editing role; the
# `require_writable_move!` before_action also redirects an archived (read-only)
# Move with the friendly alert. The Menu link is hidden for non-editors so there
# is no dead-end 403.
class BoxStepsController < MoveScopedController
  before_action { Current.nav_section = :menu }
  # `show` is an editor-only planning surface (it offers mutating buttons), so it
  # gets the same writable+editor guard as `create` — a viewer never sees it.
  before_action :require_writable_move!, only: %i[show create]

  # Cap how many skipped box numbers appear in the flash. The flash rides the
  # :cookie_store session (4 KB), so a move with hundreds of roomless boxes would
  # otherwise overflow the cookie and turn the redirect into an error instead of
  # the summary (Codex). The remainder is summarised as "… and N more".
  MAX_SKIPPED_NUMBERS = 20

  # GET /moves/:move_id/box_steps
  def show
    counts = state_counts
    render Views::BoxSteps::Show.new(
      move: @move,
      counts: counts,
      steps: Boxes::BulkTransition::STEPS.select { |step| counts.fetch(step[:from], 0).positive? }
    )
  end

  # POST /moves/:move_id/box_steps
  def create
    result = Boxes::BulkTransition.new.call(move: @move, to: params[:to], actor: current_user)

    case result
    in Dry::Monads::Success(summary)
      redirect_to move_box_steps_path(@move), notice: summary_flash(summary)
    in Dry::Monads::Failure(:invalid_step)
      redirect_to move_box_steps_path(@move), alert: t(".invalid_step")
    in Dry::Monads::Failure(:move_archived)
      redirect_to read_only_redirect_path, alert: t("moves.archived_alert")
    end
  end

  private

  # Where require_writable_move! sends an editor who tried to act on an archived
  # Move — back to the Menu, the surface this page is reached from.
  def read_only_redirect_path
    move_menu_path(@move)
  end

  # SQL state distribution (AGENTS.md §1 #5): one GROUP BY, never pluck.tally.
  def state_counts
    @move.boxes.group(:status).count
  end

  # "Sealed 10 boxes. 2 skipped (need a room first): 5, 6." — names what moved and
  # what didn't (with box numbers + reason) so a partial seal is self-explanatory.
  def summary_flash(summary)
    # When nothing moved but boxes were skipped, lead with the skipped sentence
    # alone — the "no boxes were in that state" copy would be wrong (boxes WERE
    # there; they just couldn't advance), pointing the user at the wrong fix.
    return skipped_sentence(summary.skipped) if summary.transitioned.zero? && summary.skipped.any?

    moved = t(".transitioned", count: summary.transitioned, status: t("boxes.status.#{summary.to}"))
    return moved if summary.skipped.empty?

    "#{moved} #{skipped_sentence(summary.skipped)}"
  end

  def skipped_sentence(skipped)
    # Every forward step has exactly one skip reason today (:room_required on a
    # seal); surface it by reason so the copy stays accurate if more are added.
    reason = t("box_steps.skip_reason.#{skipped.first[:reason]}", default: t("box_steps.skip_reason.default"))
    t(".skipped", count: skipped.size, reason: reason, numbers: skipped_numbers(skipped))
  end

  def skipped_numbers(skipped)
    shown = skipped.first(MAX_SKIPPED_NUMBERS).pluck(:number).join(", ")
    remainder = skipped.size - MAX_SKIPPED_NUMBERS
    return shown unless remainder.positive?

    t("box_steps.create.skipped_overflow", numbers: shown, count: remainder)
  end
end
