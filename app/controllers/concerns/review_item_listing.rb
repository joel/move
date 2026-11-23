# frozen_string_literal: true

# The per-photo review item list (C2) and how it streams: the photo's in-box
# items, the conflicts its latest run left for a person to settle (#891/#881),
# the ?queue=move walk params, and the Turbo Stream that replaces the list in
# place. Used by ReviewsController's item add/remove and conflict resolution
# (ReviewConflictResponses), so all of them re-render the same list. Expects the including controller to set @move, @box and @media and to
# include FindListPinnable.
# NB: concern modules are unchecked by Steep (Steepfile note); this module's
# surface is declared in sig/concerns.rbs like the other controller concerns.
module ReviewItemListing
  extend ActiveSupport::Concern

  private

  # Every in-box item detected in (or hand-added to) this photo, in detection
  # order. Manual review-time additions carry source_media so they join the list.
  def photo_items(media)
    @box.items.in_box.where(source_media_id: media.id).order(:created_at)
  end

  # The conflicts this photo's LATEST run recorded (#891, the capture panel's
  # #872 rule): detections that matched an item already confirmed here, so no
  # item was created. Each needs a person's call (#881: same item / keep both).
  # The match must still be in this box (kept, in_box). A lazy relation with
  # the matched item preloaded, ordered by its name.
  def conflict_suggestions
    RecognitionSuggestion.latest_conflicts_for(@media.id)
                         .joins(:item).merge(Item.in_box.where(box_id: @box.id))
                         .includes(:item).order("items.name", :created_at)
  end

  def queue_mode?
    params[:queue] == ReviewsController::QUEUE_PARAM
  end

  # Splat into path helpers so box-mode URLs stay byte-identical (no ?queue=).
  def queue_query
    queue_mode? ? { queue: ReviewsController::QUEUE_PARAM } : {}
  end

  def review_list_stream(items, highlight_id: nil)
    turbo_stream.replace(
      Components::Reviews::ItemList::ID,
      view_context.render(Components::Reviews::ItemList.new(
                            move: @move, box: @box, media: @media, items: items, editable: editable_move?,
                            conflicts: conflict_suggestions, highlight_id: highlight_id, queue: queue_mode?,
                            pinnable: pinnable?, pinned_item_ids: pinned_item_ids
                          ))
    )
  end
end
