# frozen_string_literal: true

module Views
  module Galleries
    # Gallery — every photo across a Move in one recent-first grid, filterable by
    # room and sortable, opening a lightbox on tap. The Move-wide companion to the
    # per-box ContentsGrid (B1). Renders inside the AppLayout sidebar shell.
    class Index < Views::Base
      include Phlex::Rails::Helpers::FormWith

      SORTS = %w[recent oldest].freeze

      def initialize(move:, media:, rooms:, sort_key:, selected_room_id: nil, over_cap: false)
        @move = move
        @media = media
        @rooms = rooms
        @sort_key = sort_key
        @selected_room_id = selected_room_id
        @over_cap = over_cap
      end

      def view_template
        div(class: "flex flex-col gap-section-gap") do
          header
          controls
          cap_notice if @over_cap
          @media.any? ? grid : empty_state
        end
      end

      private

      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: @move.name,
          title: I18n.t("galleries.index.title"),
          subtitle: I18n.t("galleries.index.subtitle")
        )
      end

      def cap_notice
        p(class: "text-body-md text-on-surface-variant") do
          I18n.t("galleries.index.capped.#{@sort_key}", count: GalleriesController::CAP)
        end
      end

      # Room filter (left) + sort (right), both GET-param driven so they survive
      # each other and stay bookmarkable — mirrors Views::Boxes::Index.
      def controls
        return unless @rooms.any? || @media.any?

        div(class: "flex flex-col gap-3 sm:flex-row sm:items-center") do
          filters if @rooms.any?
          div(class: "sm:ml-auto") { sort_control } if @media.any?
        end
      end

      def filters
        div(class: "flex gap-3 overflow-x-auto pb-1") do
          chip_link(I18n.t("galleries.index.filters.all"), gallery_path_with(room_id: nil), @selected_room_id.nil?)
          @rooms.each do |room|
            chip_link(room.name, gallery_path_with(room_id: room.id), @selected_room_id == room.id)
          end
        end
      end

      def chip_link(label, href, selected)
        a(href: href, class: "flex-shrink-0") do
          render Components::Ui::Chip.new(label: label, kind: :room, selected: selected)
        end
      end

      # Keep the active non-default sort when switching rooms (mirror of the sort
      # control carrying room_id), so neither control resets the other.
      def gallery_path_with(room_id:)
        query = { room_id: room_id, sort: (@sort_key unless @sort_key == "recent") }
        move_gallery_path(@move, query.compact)
      end

      def sort_control
        form_with(url: move_gallery_path(@move), method: :get, data: { controller: "auto-submit" }) do
          input(type: "hidden", name: "room_id", value: @selected_room_id) if @selected_room_id
          label(class: "flex items-center gap-2 text-label-caps uppercase text-muted") do
            span { I18n.t("galleries.index.sort.label") }
            select(
              name: "sort",
              aria_label: I18n.t("galleries.index.sort.label"),
              data: { action: "change->auto-submit#submit" },
              class: "rounded-full border border-card-border bg-card px-4 py-2 text-body-md " \
                     "normal-case tracking-normal text-text-warm focus:outline-none " \
                     "focus:ring-2 focus:ring-accent-sage/40"
            ) do
              SORTS.each do |key|
                option(value: key, selected: key == @sort_key) { I18n.t("galleries.index.sort.#{key}") }
              end
            end
          end
        end
      end

      def grid
        render Components::Gallery::Grid.new(move: @move, media: @media)
      end

      def empty_state
        if @selected_room_id
          render Components::Ui::EmptyState.new(
            icon: Components::Icons::Camera,
            title: I18n.t("galleries.index.empty.filtered_title"),
            description: I18n.t("galleries.index.empty.filtered_description")
          ) do
            render Components::Ui::Button.new(
              label: I18n.t("galleries.index.filters.clear"),
              href: move_gallery_path(@move),
              variant: :ghost
            )
          end
        else
          render Components::Ui::EmptyState.new(
            icon: Components::Icons::Camera,
            title: I18n.t("galleries.index.empty.title"),
            description: I18n.t("galleries.index.empty.description")
          )
        end
      end
    end
  end
end
