# frozen_string_literal: true

module Components
  module FindLists
    # The search page's pill into the find list (#730): "Find list · 3".
    # ALWAYS rendered (empty when the count is zero) so pin/unpin streams have
    # a guaranteed replace target — the Vocabularies stable-wrapper lesson.
    class SearchLink < Components::Base
      ID = "find-list-search-link"

      #: (move: untyped, count: Integer) -> void
      def initialize(move:, count:)
        @move = move
        @count = count
      end

      #: () -> void
      def view_template
        div(id: ID, class: "flex justify-center") do
          pill if @count.positive?
        end
      end

      private

      #: () -> untyped
      def pill
        a(
          href: move_find_list_path(@move),
          class: "mt-3 inline-flex items-center gap-2 rounded-full bg-accent-sage/15 px-4 py-1.5 " \
                 "text-label-caps uppercase text-accent-sage transition hover:bg-accent-sage/25"
        ) do
          render Components::Icons::Check.new(css: "h-3.5 w-3.5")
          plain I18n.t("find_lists.search_link", count: @count)
        end
      end
    end
  end
end
