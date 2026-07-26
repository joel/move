# frozen_string_literal: true

module Components
  module FindLists
    # The find list body (#730): count summary + Clear found, then the pins
    # grouped by box — "Box 7 · Bedroom" headers linking to the box detail's
    # in-place unpacking checklist (the header locates, rows enumerate —
    # inverting the gallery-group presentation). Stable id so every stream
    # replaces this guaranteed-present wrapper (the Vocabularies pattern), and
    # the empty↔populated boundary lives in one place.
    class List < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      ID = "find-list"

      #: (move: untyped, entries: untyped) -> void
      def initialize(move:, entries:)
        @move = move
        @entries = entries.to_a
        @found = @entries.count { |entry| entry.item.removed? }
      end

      #: () -> void
      def view_template
        div(id: ID, class: "flex flex-col gap-stack-gap") do
          @entries.any? ? body : empty_state
        end
      end

      private

      #: () -> untyped
      def body
        summary_bar
        @entries.group_by { |entry| entry.item.box }.each do |box, entries|
          box_group(box, entries)
        end
      end

      #: () -> untyped
      def summary_bar
        div(class: "flex items-center justify-between px-2") do
          span(class: "text-label-caps uppercase text-muted") do
            I18n.t("find_lists.show.found_count", found: @found, total: @entries.size)
          end
          clear_found_control if @found.positive?
        end
      end

      #: () -> untyped
      def clear_found_control
        button_to(view_context.move_find_list_clear_found_path(@move),
                  method: :delete,
                  class: "rounded-full px-4 py-1.5 text-label-caps uppercase text-accent-sage " \
                         "transition hover:bg-accent-sage/15") do
          I18n.t("find_lists.show.clear_found")
        end
      end

      #: (untyped box, untyped entries) -> untyped
      def box_group(box, entries)
        section(class: "flex flex-col gap-2") do
          a(href: view_context.move_box_path(@move, box),
            class: "flex items-center gap-2 px-2 text-headline-md text-text-warm transition " \
                   "hover:text-accent-sage") do
            render Components::Icons::Boxes.new(css: "h-5 w-5 text-accent-sage")
            plain box_label(box)
            render Components::Icons::ChevronRight.new(css: "h-4 w-4 text-muted")
          end
          ul(class: "flex flex-col gap-2") do
            entries.each { |entry| render Components::FindLists::Row.new(move: @move, entry: entry) }
          end
        end
      end

      #: (untyped box) -> String
      def box_label(box)
        parts = [I18n.t("find_lists.show.box_label", number: box.number)]
        parts << box.room.name if box.room
        parts.join(" · ")
      end

      #: () -> untyped
      def empty_state
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Search,
          title: I18n.t("find_lists.show.empty.title"),
          description: I18n.t("find_lists.show.empty.description")
        )
        div(class: "flex justify-center") do
          a(href: view_context.move_search_path(@move),
            class: Components::Ui::Button.classes(variant: :secondary)) do
            I18n.t("find_lists.show.empty.cta")
          end
        end
      end
    end
  end
end
