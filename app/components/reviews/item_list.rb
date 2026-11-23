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
      # @rbs conflicts: untyped
      # @rbs editable: untyped
      # @rbs highlight_id: untyped
      # @rbs queue: untyped
      # @rbs pinnable: bool
      # @rbs pinned_item_ids: untyped
      # @rbs return: void
      def initialize(move:, box:, media:, items:, editable:, conflicts: [], highlight_id: nil,
                     queue: false, pinnable: false, pinned_item_ids: Set.new)
        @move = move
        @box = box
        @media = media
        @items = items.to_a
        # Conflict suggestions the photo's latest run left to settle (#891/#881),
        # each with its matched item preloaded.
        @conflicts = conflicts.to_a
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
            conflict_section if @conflicts.any?
          end
        end
      end

      private

      #: () -> untyped
      def empty_state
        return conflict_empty_state if @conflicts.any?

        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Camera,
          title: I18n.t("reviews.photo.empty_title"),
          description: I18n.t("reviews.photo.empty_description")
        )
      end

      # A conflict-only photo (#891): recognition matched items already confirmed
      # in this box, so it added none. Say so and list each match with its
      # resolve controls (#881).

      #: () -> untyped
      def conflict_empty_state
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Camera,
          title: I18n.t("reviews.photo.conflict_title"),
          description: I18n.t("reviews.photo.conflict_description", count: @conflicts.size)
        ) { conflict_list }
      end

      # A photo with items of its own AND matches (#881): the matches still need
      # a call, so they follow the rows instead of hiding behind them.

      #: () -> untyped
      def conflict_section
        section(class: "mt-6 flex flex-col gap-3", aria: { labelledby: "review-conflicts-title" }) do
          h3(id: "review-conflicts-title", class: "text-headline-md text-text-warm") do
            I18n.t("reviews.photo.conflict_title")
          end
          p(class: "text-body-md text-on-surface-variant") do
            I18n.t("reviews.photo.conflict_section_description", count: @conflicts.size)
          end
          conflict_list
        end
      end

      #: () -> untyped
      def conflict_list
        render Components::Reviews::ConflictList.new(
          move: @move, box: @box, media: @media, conflicts: @conflicts, editable: @editable, queue: @queue
        )
      end
    end
  end
end
