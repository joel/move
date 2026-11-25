# frozen_string_literal: true

module Components
  module Items
    # C3's back link (#960, UX rule 4): returns the user to where they opened the
    # item from. The search results and find-list links tag the item URL with
    # `from=search` (plus the query) or `from=find_list`; any other or missing
    # value falls back to the item's box. The destination is only ever built
    # from route helpers chosen by that allow-list, never from a URL in params,
    # so the link cannot become an open redirect. The fragment lands the user
    # back on the card they opened.
    class BackLink < Components::Base
      SEARCH = "search"
      FIND_LIST = "find_list"

      # The anchor the origin page renders on the item's card or row.

      #: (untyped item) -> String
      def self.search_anchor(item) = "search-result-#{item.id}"

      #: (untyped item) -> String
      def self.find_list_anchor(item) = "find-list-item-#{item.id}"

      #: (move: untyped, item: untyped, ?from: untyped, ?query: untyped) -> void
      def initialize(move:, item:, from: nil, query: nil)
        @move = move
        @item = item
        @from = from.to_s
        @query = query.to_s.strip
      end

      #: () -> void
      def view_template
        href, label = destination
        a(
          href: href,
          class: "inline-flex items-center gap-2 text-label-caps uppercase text-muted hover:text-text-warm"
        ) do
          render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-180")
          plain label
        end
      end

      private

      #: () -> [String, String]
      def destination
        if @from == SEARCH && @query.present?
          [move_search_path(@move, q: @query, anchor: self.class.search_anchor(@item)),
           I18n.t("items.show.back_to_results")]
        elsif @from == FIND_LIST
          [move_find_list_path(@move, anchor: self.class.find_list_anchor(@item)),
           I18n.t("items.show.back_to_find_list")]
        else
          [move_box_path(@move, @item.box), I18n.t("items.show.back")]
        end
      end
    end
  end
end
