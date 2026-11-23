# frozen_string_literal: true

# The responses for ReviewsController#dismiss_conflict / #keep_both_conflict
# (#881): the photo's item list re-rendered in place with a toast linking to the
# item the decision is about (UX rule 1), or — on a stale tab, a double-submit,
# a re-scan or an unpacked box — the list as it is now with a notice saying why
# nothing changed. HTML clients are redirected back to the photo. Expects the
# including controller to set @move, @box and @media and to include
# ReviewItemListing (ReviewsController).
# NB: concern modules are unchecked by Steep (Steepfile note); this module's
# surface is declared in sig/concerns.rbs like the other controller concerns.
module ReviewConflictResponses
  extend ActiveSupport::Concern

  private

  def resolve_conflict(outcome)
    RecognitionSuggestions::ResolveConflict.new.call(suggestion: @suggestion, actor: current_user, outcome:)
  end

  def conflict_resolved_response(message, item, highlight_id: nil)
    link = { action_href: move_item_path(@move, item), action_label: t("reviews.flash.view_item") }
    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = message
        link.each { |key, value| flash.now[key] = value }
        render turbo_stream: [review_list_stream(photo_items(@media).to_a, highlight_id:),
                              turbo_stream.replace(Components::FlashToasts::ID, Components::FlashToasts.new)]
      end
      format.html { redirect_to conflict_photo_path, notice: message, flash: link }
    end
  end

  def conflict_refused_response(reason)
    respond_with_streams(-> { review_list_stream(photo_items(@media).to_a) },
                         redirect: conflict_photo_path, toast: true, status: :unprocessable_content) do
      [:alert, conflict_refusal_message(reason)]
    end
  end

  def conflict_refusal_message(reason)
    case reason
    when :not_conflict, :superseded, :stale then t("reviews.flash.conflict_stale")
    when :box_unpacked then t("reviews.flash.conflict_box_unpacked")
    when :move_archived then t("moves.archived_alert")
    else t("reviews.flash.conflict_failed")
    end
  end

  def conflict_photo_path
    move_box_review_photo_path(@move, @box, @media, **queue_query)
  end
end
