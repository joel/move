# frozen_string_literal: true

# C1 — Review queue (index) and C2 — Review item-by-item (show) for one Box, plus
# the per-suggestion resolution actions (keep / correct / mark_false_positive).
# Runs inside an Organization tenant schema. Thin: authorize, call the action,
# advance through the queue.
class RecognitionSuggestionsController < ApplicationController
  layout -> { Views::Layouts::AppShellLayout }

  before_action :require_authenticated_user!
  before_action :require_tenant!
  before_action :set_move
  before_action :set_box
  before_action :set_suggestion, only: %i[show keep correct mark_false_positive]
  before_action :require_writable_move!, only: %i[keep correct mark_false_positive]

  # GET /moves/:move_id/boxes/:box_id/review
  def index
    render Views::Reviews::Queue.new(
      move: @move, box: @box,
      queue: queue_suggestions,
      counts: review_counts,
      first_unreviewed: queue_suggestions.first
    )
  end

  # GET /moves/:move_id/boxes/:box_id/review/:id
  def show
    render Views::Reviews::Item.new(
      move: @move, box: @box, suggestion: @suggestion,
      position: review_position(@suggestion), total: reviewable_total
    )
  end

  # PATCH .../review/:id/keep
  def keep
    RecognitionSuggestions::Keep.new.call(suggestion: @suggestion, actor: current_user)
    advance(notice: t("reviews.flash.kept", name: @suggestion.proposed_name))
  end

  # PATCH .../review/:id/correct — confirm, then open the C3 item edit prefilled.
  def correct
    result = RecognitionSuggestions::Correct.new.call(suggestion: @suggestion, actor: current_user)

    case result
    in Dry::Monads::Success(suggestion)
      redirect_to move_item_path(@move, suggestion.item), notice: t("reviews.flash.correcting")
    in Dry::Monads::Failure(_)
      advance(alert: t("reviews.flash.cannot_correct"))
    end
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

  def review_counts
    items = @box.items
    {
      pending: items.where(review_state: "pending_review").count,
      needs_correction: items.where(review_state: "needs_correction").count,
      auto_confirmed: items.where(review_state: "auto_confirmed").count
    }
  end

  def set_move
    @move = authorized_scope(Move.all).find(params.expect(:move_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
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

  def require_tenant!
    head :not_found unless current_tenant
  end

  def require_writable_move!
    return if @move.writable?

    redirect_to move_box_review_index_path(@move, @box), alert: t("items.archived")
  end
end
