# frozen_string_literal: true

module Views
  module FindLists
    # The personal find list (#730): the caller's pinned items rolled up by box
    # so they can sweep one box at a time; entries strike automatically once
    # their item is unpacked. Renders inside the AppLayout shell (nav: search —
    # this surface is the search flow's companion).
    class Show < Views::Base
      #: (move: untyped, entries: untyped, editable: untyped) -> void
      def initialize(move:, entries:, editable:)
        @move = move
        @entries = entries
        @editable = editable
      end

      #: () -> void
      def view_template
        div(class: "flex flex-col gap-stack-gap", data: { controller: "refocus" }) do
          render Components::Ui::SectionHeader.new(
            eyebrow: @move.name,
            title: I18n.t("find_lists.show.title"),
            subtitle: I18n.t("find_lists.show.subtitle")
          )
          render Components::FindLists::List.new(move: @move, entries: @entries, editable: @editable)
        end
      end
    end
  end
end
