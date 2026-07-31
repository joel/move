# frozen_string_literal: true

module Components
  module Reviews
    # C2 — the per-photo detected-item list. Stable ids so ReviewsController can
    # stream mutations without a reload: append a new ItemRow to the inner rows
    # container (ROWS_ID), or replace the whole list (ID) at the empty boundary —
    # last item removed (list → empty state) or first item added (empty → list).
    class ItemList < Components::Base
      ID = "review-item-list"
      ROWS_ID = "review-item-rows"

      # highlight_id: when the list is re-rendered after adding the first item to a
      # previously-empty photo, flag that one row so it scrolls into view + rings.
      # queue: the Move-wide walk (#654) — row mutation URLs carry ?queue=move so
      # the no-JS fallbacks redirect back into the walk, not box mode.
      # pinnable/pinned_item_ids: the find-list pin on each row (#749, closed
      # box) — personal state, not editable-gated (viewers pin).

      # @rbs move: untyped
      # @rbs box: untyped
      # @rbs media: untyped
      # @rbs items: untyped
      # @rbs editable: untyped
      # @rbs highlight_id: untyped
      # @rbs queue: untyped
      # @rbs pinnable: bool
      # @rbs pinned_item_ids: untyped
      # @rbs return: void
      def initialize(move:, box:, media:, items:, editable:, highlight_id: nil, queue: false,
                     pinnable: false, pinned_item_ids: Set.new)
        @move = move
        @box = box
        @media = media
        @items = items.to_a
        @editable = editable
        @highlight_id = highlight_id
        @queue = queue
        @pinnable = pinnable
        @pinned_item_ids = pinned_item_ids
      end

      #: () -> void
      def view_template
        # `refocus` keeps keyboard focus on a pin toggle across its stream swap
        # (#749) — the same convention as the search and box-contents grids.
        div(id: ID, data: { controller: "refocus" }) do
          if @items.empty?
            empty_state
          else
            div(id: ROWS_ID, class: "mt-5 flex flex-col gap-stack-gap") do
              @items.each do |item|
                render Components::Reviews::ItemRow.new(
                  move: @move, box: @box, media: @media, item:,
                  editable: @editable, highlight: item.id == @highlight_id, queue: @queue,
                  pinnable: @pinnable, pinned: @pinned_item_ids.include?(item.id)
                )
              end
            end
          end
        end
      end

      private

      #: () -> untyped
      def empty_state
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Camera,
          title: I18n.t("reviews.photo.empty_title"),
          description: I18n.t("reviews.photo.empty_description")
        )
      end
    end
  end
end
