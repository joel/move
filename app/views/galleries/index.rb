# frozen_string_literal: true

module Views
  module Galleries
    # Gallery — every photo across a Move in one recent-first grid, filterable by
    # room and sortable, opening a lightbox on tap. The Move-wide companion to the
    # per-box ContentsGrid (B1). Renders inside the AppLayout sidebar shell.
    class Index < Views::Base
      include Phlex::Rails::Helpers::FormWith

      SORTS = %w[recent oldest].freeze

      #: (move: untyped, media: untyped, rooms: untyped, sort_key: untyped, ?selected_room_id: untyped, ?cursor: untyped, ?remaining: Integer) -> void
      def initialize(move:, media:, rooms:, sort_key:, selected_room_id: nil, cursor: nil, remaining: 0)
        @move = move
        @media = media
        @rooms = rooms
        @sort_key = sort_key
        @selected_room_id = selected_room_id
        @cursor = cursor
        @remaining = remaining
      end

      #: () -> void
      def view_template
        div(class: "flex flex-col gap-section-gap") do
          header
          render Components::Gallery::ViewToggle.new(move: @move, active: "photos")
          controls
          @media.any? ? grid_with_pager : empty_state
        end
      end

      private

      #: () -> untyped
      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: @move.name,
          title: I18n.t("galleries.index.title"),
          subtitle: I18n.t("galleries.index.subtitle")
        )
      end

      # Room filter (left) + sort (right), both GET-param driven so they survive
      # each other and stay bookmarkable — mirrors Views::Boxes::Index.

      #: () -> untyped
      def controls
        return unless @rooms.any? || @media.any?

        div(class: "flex flex-col gap-3 sm:flex-row sm:items-center") do
          filters if @rooms.any?
          div(class: "sm:ml-auto") { sort_control } if @media.any?
        end
      end

      #: () -> untyped
      def filters
        div(class: "flex gap-3 overflow-x-auto pb-1") do
          chip_link(I18n.t("galleries.index.filters.all"), gallery_path_with(room_id: nil), @selected_room_id.nil?)
          @rooms.each do |room|
            chip_link(room.name, gallery_path_with(room_id: room.id), @selected_room_id == room.id)
          end
        end
      end

      #: (untyped label, untyped href, bool selected) -> untyped
      def chip_link(label, href, selected)
        a(href: href, class: "flex-shrink-0") do
          render Components::Ui::Chip.new(label: label, kind: :room, selected: selected)
        end
      end

      # Keep the active non-default sort when switching rooms (mirror of the sort
      # control carrying room_id), so neither control resets the other.

      #: (room_id: untyped) -> untyped
      def gallery_path_with(room_id:)
        query = { room_id: room_id, sort: (@sort_key unless @sort_key == "recent") }
        move_gallery_path(@move, query.compact)
      end

      #: () -> untyped
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

      # The pager renders below the grid whenever photos are shown — its wrapper
      # is the stable turbo_stream replace target for "Load more" (#718), so it
      # must exist even when nothing remains (it then carries no chrome).

      #: () -> untyped
      def grid_with_pager
        render Components::Gallery::Grid.new(move: @move, media: @media)
        render Components::Gallery::Pager.new(
          move: @move, cursor: @cursor, remaining: @remaining,
          sort_key: @sort_key, selected_room_id: @selected_room_id
        )
      end

      #: () -> untyped
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
