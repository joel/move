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
      # @rbs conflict_items: untyped
      # @rbs editable: untyped
      # @rbs highlight_id: untyped
      # @rbs queue: untyped
      # @rbs pinnable: bool
      # @rbs pinned_item_ids: untyped
      # @rbs return: void
      def initialize(move:, box:, media:, items:, editable:, conflict_items: [], highlight_id: nil,
                     queue: false, pinnable: false, pinned_item_ids: Set.new)
        @move = move
        @box = box
        @media = media
        @items = items.to_a
        # Confirmed items the photo's latest run matched instead of creating its
        # own (#891) — a lazy relation, loaded only for the empty state.
        @conflict_items = conflict_items
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
        matches = @conflict_items.to_a
        return conflict_empty_state(matches) if matches.any?

        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Camera,
          title: I18n.t("reviews.photo.empty_title"),
          description: I18n.t("reviews.photo.empty_description")
        )
      end

      # A conflict-only photo (#891): recognition matched items already confirmed
      # in this box, so it added none. Say so and link to each match. Kept simple
      # on purpose — #881 adds the real resolve actions (dismiss / keep both).

      #: (Array[untyped] matches) -> untyped
      def conflict_empty_state(matches)
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Camera,
          title: I18n.t("reviews.photo.conflict_title"),
          description: I18n.t("reviews.photo.conflict_description", count: matches.size)
        ) do
          matches.each do |item|
            a(href: move_item_path(@move, item),
              class: "inline-flex items-center gap-1 rounded-full bg-surface-container-high px-3 py-1.5 " \
                     "text-label-caps uppercase text-on-surface-variant transition hover:text-accent-sage") do
              plain item.name
              render Components::Icons::ChevronRight.new(css: "h-3.5 w-3.5")
            end
          end
        end
      end
    end
  end
end
