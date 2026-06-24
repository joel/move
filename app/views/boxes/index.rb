# frozen_string_literal: true

module Views
  module Boxes
    # A2 — Boxes Home. The hub of a Move: a compact progress indicator, a room
    # filter, and the box grid (with a "Start New Box" tile). Renders inside the
    # AppLayout sidebar shell (see AppShellLayout).
    class Index < Views::Base
      include Phlex::Rails::Helpers::FormWith

      def initialize(move:, boxes:, rooms:, summary:, sort_key: Box::DEFAULT_SORT,
                     selected_room_id: nil, item_counts: {}, editable: false,
                     highlight_box_id: nil)
        @move = move
        @boxes = boxes
        @rooms = rooms
        @summary = summary
        @sort_key = sort_key
        @selected_room_id = selected_room_id
        @item_counts = item_counts
        @editable = editable
        @highlight_box_id = highlight_box_id
      end

      def view_template
        @boxes.load # one query, reused by the any?/each calls below
        header
        progress_summary
        controls
        @boxes.any? ? grid : empty_state
      end

      private

      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: I18n.t("moves.status.#{@move.status}", default: @move.status.titleize),
          title: I18n.t("boxes.index.title"),
          subtitle: @move.name
        ) do
          add_button if @editable
        end
      end

      def add_button
        render Components::Ui::Button.new(
          label: I18n.t("boxes.index.add"),
          icon: Components::Icons::Plus,
          href: new_move_box_path(@move)
        )
      end

      # Move-wide progress: packed ratio + pending-review and missing-dimensions
      # counts (Domain §4 progress indicator). Item counts arrive in D5.
      def progress_summary
        render Components::Ui::Card.new do
          div(class: "flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between") do
            div(class: "w-full sm:max-w-xs") do
              render Components::Ui::ProgressBar.new(
                value: @summary[:sealed], max: [@summary[:total], 1].max,
                label: I18n.t("boxes.summary.packed")
              )
            end
            div(class: "flex gap-section-gap") do
              stat(@summary[:pending_review], I18n.t("boxes.summary.pending_review"))
              stat(@summary[:missing_dimensions], I18n.t("boxes.summary.missing_dimensions"))
            end
          end
        end
      end

      def stat(value, label)
        div(class: "flex flex-col") do
          span(class: "text-headline-md text-text-warm") { value.to_s }
          span(class: "text-label-caps uppercase text-muted") { label }
        end
      end

      # Room filter (left) + sort control (right), both GET-param driven so the
      # active room and sort survive each other and stay bookmarkable. Filters show
      # whenever the Move has rooms — even on an empty filtered result, so the user
      # can always switch rooms; the sort control only when there are boxes to sort.
      # `ml-auto` right-aligns the sort without a spacer element.
      def controls
        return unless @rooms.any? || @boxes.any?

        div(class: "flex flex-col gap-3 sm:flex-row sm:items-center") do
          filters if @rooms.any?
          div(class: "sm:ml-auto") { sort_control } if @boxes.any?
        end
      end

      def filters
        div(class: "flex gap-3 overflow-x-auto pb-1") do
          chip_link(I18n.t("boxes.filters.all"), boxes_path_with(room_id: nil), @selected_room_id.nil?)
          @rooms.each do |room|
            chip_link(room.name, boxes_path_with(room_id: room.id), @selected_room_id == room.id)
          end
        end
      end

      # Filter links keep the active non-default sort so switching rooms doesn't
      # reset it — the mirror of the sort control carrying room_id (#336 review).
      def boxes_path_with(room_id:)
        query = { room_id: room_id, sort: (@sort_key unless @sort_key == Box::DEFAULT_SORT) }
        move_boxes_path(@move, query.compact)
      end

      # Auto-submitting GET select (Phlex blocks inline on* handlers, so the
      # submit is driven by the `auto-submit` Stimulus controller — same pattern as
      # Settings labels-per-box). Carries the active room filter through.
      def sort_control
        form_with(url: move_boxes_path(@move), method: :get,
                  data: { controller: "auto-submit" }) do
          input(type: "hidden", name: "room_id", value: @selected_room_id) if @selected_room_id
          label(class: "flex items-center gap-2 text-label-caps uppercase text-muted") do
            span { I18n.t("boxes.index.sort.label") }
            select(
              name: "sort",
              aria_label: I18n.t("boxes.index.sort.label"),
              data: { action: "change->auto-submit#submit" },
              class: "rounded-full border border-card-border bg-card px-4 py-2 text-body-md " \
                     "normal-case tracking-normal text-text-warm focus:outline-none " \
                     "focus:ring-2 focus:ring-accent-sage/40"
            ) do
              Box::SORTS.each_key do |key|
                option(value: key, selected: key == @sort_key) do
                  I18n.t("boxes.index.sort.#{key}")
                end
              end
            end
          end
        end
      end

      def chip_link(label, href, selected)
        a(href: href, class: "flex-shrink-0") do
          render Components::Ui::Chip.new(label: label, kind: :room, selected: selected)
        end
      end

      # The grid only renders when boxes exist, so the dashed "Start New Box" card
      # would only ever appear alongside existing boxes — redundant with the green
      # "+ Add box" button in the header. Dropped (#260); the empty state (no boxes)
      # keeps its own Add CTA.
      def grid
        div(class: "grid grid-cols-1 gap-stack-gap sm:grid-cols-2 lg:grid-cols-3") do
          @boxes.each do |box|
            render Components::BoxCard.new(
              box: box, item_count: @item_counts[box.id].to_i,
              highlight: box.id == @highlight_box_id
            )
          end
        end
      end

      def empty_state
        if @selected_room_id
          render Components::Ui::EmptyState.new(
            title: I18n.t("boxes.empty.filtered_title"),
            description: I18n.t("boxes.empty.filtered_description")
          ) do
            render Components::Ui::Button.new(
              label: I18n.t("boxes.filters.clear"),
              href: move_boxes_path(@move),
              variant: :ghost
            )
          end
        else
          render Components::Ui::EmptyState.new(
            title: I18n.t("boxes.empty.title"),
            description: I18n.t("boxes.empty.description")
          ) { add_button if @editable }
        end
      end
    end
  end
end
