# frozen_string_literal: true

module Views
  module Boxes
    # A2 — Boxes Home. The hub of a Move: a compact progress indicator, a room
    # filter, and the box grid (with a "Start New Box" tile). Renders inside the
    # AppLayout sidebar shell (see AppShellLayout).
    class Index < Views::Base
      def initialize(move:, boxes:, rooms:, summary:, selected_room_id: nil)
        @move = move
        @boxes = boxes
        @rooms = rooms
        @summary = summary
        @selected_room_id = selected_room_id
      end

      def view_template
        header
        progress_summary
        filters if @rooms.any?
        @boxes.any? ? grid : empty_state
      end

      private

      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: I18n.t("moves.status.#{@move.status}", default: @move.status.titleize),
          title: I18n.t("boxes.index.title"),
          subtitle: @move.name
        ) do
          add_button if @move.writable?
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

      def filters
        div(class: "flex gap-3 overflow-x-auto pb-1") do
          chip_link(I18n.t("boxes.filters.all"), move_boxes_path(@move), @selected_room_id.nil?)
          @rooms.each do |room|
            chip_link(room.name, move_boxes_path(@move, room_id: room.id), @selected_room_id == room.id)
          end
        end
      end

      def chip_link(label, href, selected)
        a(href: href, class: "flex-shrink-0") do
          render Components::Ui::Chip.new(label: label, kind: :room, selected: selected)
        end
      end

      def grid
        div(class: "grid grid-cols-1 gap-stack-gap sm:grid-cols-2 lg:grid-cols-3") do
          @boxes.each { |box| render Components::BoxCard.new(box: box) }
          start_new_box_card if @move.writable?
        end
      end

      def start_new_box_card
        a(
          href: new_move_box_path(@move),
          class: "flex flex-col gap-4 rounded-card border border-dashed border-card-border " \
                 "bg-card p-5 transition hover:-translate-y-0.5 hover:bg-surface-container-high"
        ) do
          div(
            class: "flex h-12 w-12 items-center justify-center rounded-full " \
                   "border border-dashed border-card-border text-muted"
          ) { render Components::Icons::Plus.new(css: "h-6 w-6") }
          div(class: "mt-auto") do
            h3(class: "mb-1 text-headline-md text-text-warm opacity-80") do
              I18n.t("boxes.index.start_new")
            end
            p(class: "text-body-md text-muted opacity-70") { I18n.t("boxes.index.start_new_hint") }
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
          ) { add_button if @move.writable? }
        end
      end
    end
  end
end
