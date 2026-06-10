# frozen_string_literal: true

# C1 — Review queue (index) and C2 — Review item-by-item (show) for one Box, plus
# the per-suggestion resolution actions (keep / correct / mark_false_positive).
# Runs inside an Organization tenant schema. Thin: authorize, call the action,
# advance through the queue.
class RecognitionSuggestionsController < MoveScopedController
  before_action :set_box
  before_action :set_suggestion, only: %i[show keep correct mark_false_positive]
  before_action :require_writable_move!, only: %i[keep correct mark_false_positive]
  before_action :require_unresolved!, only: %i[keep correct mark_false_positive]

  # GET /moves/:move_id/boxes/:box_id/review
  def index
    render Views::Reviews::Queue.new(
      move: @move, box: @box,
      queue: queue_suggestions,
      counts: review_counts,
      first_unreviewed: queue_suggestions.first,
      editable: editable_move?
    )
  end

  # GET /moves/:move_id/boxes/:box_id/review/:id
  def show
    render Views::Reviews::Item.new(
      move: @move, box: @box, suggestion: @suggestion,
      position: review_position(@suggestion), total: reviewable_total,
      editable: editable_move?
    )
  end

  # PATCH .../review/:id/keep
  def keep
    RecognitionSuggestions::Keep.new.call(suggestion: @suggestion, actor: current_user)
    advance(notice: t("reviews.flash.kept", name: @suggestion.proposed_name))
  end

  # PATCH .../review/:id/correct — open the C3 item edit prefilled. The suggestion
  # stays unresolved until the edit is *saved* (ItemsController#update resolves the
  # carried review_suggestion_id), so abandoning the edit leaves it in the queue.
  def correct
    return advance(alert: t("reviews.flash.cannot_correct")) if @suggestion.item.nil?

    redirect_to move_item_path(@move, @suggestion.item, review_suggestion_id: @suggestion.id),
                notice: t("reviews.flash.correcting")
  end

  # PATCH .../review/:id/mark_false_positive
  def mark_false_positive
    RecognitionSuggestions::MarkFalsePositive.new.call(suggestion: @suggestion, actor: current_user)
    advance(notice: t("reviews.flash.ignored", name: @suggestion.proposed_name))
  end

  private

  # Move to the next unresolved suggestion (lowest confidence first), or back to
  # the box once the queue is empty.
  def advance(**flash)
    nxt = queue_suggestions.first
    if nxt
      redirect_to move_box_review_path(@move, @box, nxt), **flash
    else
      redirect_to move_box_path(@move, @box), notice: t("reviews.flash.complete")
    end
  end

  def queue_suggestions
    @queue_suggestions ||=
      authorized_scope(@box.recognition_suggestions).unresolved
                                                    .includes(media: { image_attachment: :blob }).by_confidence
  end

  # 1-based position of a still-unresolved suggestion within the review set.
  def review_position(suggestion)
    reviewable_total - queue_suggestions.count +
      (queue_suggestions.to_a.index { |s| s.id == suggestion.id } || 0) + 1
  end

  # Everything that ever needed review (excludes machine auto_accepted).
  def reviewable_total
    @reviewable_total ||= @box.recognition_suggestions.where.not(state: "auto_accepted").count
  end

  # Only items still in the box count toward review summaries — a false-positive
  # that was removed must not linger as "pending".
  def review_counts
    items = @box.items.in_box
    {
      pending: items.where(review_state: "pending_review").count,
      needs_correction: items.where(review_state: "needs_correction").count,
      auto_confirmed: items.where(review_state: "auto_confirmed").count
    }
  end

  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def set_suggestion
    @suggestion = authorized_scope(@box.recognition_suggestions).find(params.expect(:id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def require_writable_move!
    authorize_move_mutation!
    return if @move.writable?

    redirect_to move_box_review_index_path(@move, @box), alert: t("items.archived")
  end

  # Resolution actions only apply to unresolved (pending/conflict) suggestions —
  # a stale page, back-button resubmit, or crafted URL must not reclassify an
  # already-resolved or auto-accepted suggestion (e.g. remove an auto-confirmed
  # item via the ignore endpoint).
  def require_unresolved!
    return if @suggestion.unresolved?

    redirect_to move_box_review_index_path(@move, @box), notice: t("reviews.flash.already_resolved")
  end
end
