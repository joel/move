# frozen_string_literal: true

module Components
  module Items
    # C3's back link (#960, UX rule 4): returns the user to where they opened the
    # item from. The search results and find-list links tag the item URL with
    # `from=search` (plus the query) or `from=find_list`; any other or missing
    # value falls back to the item's box. `origin_params` is the allow-list: it
    # keeps only those known shapes, and the item page threads its result through
    # its own forms and redirects so actions don't drop the context. The href is
    # only ever built from route helpers, never from a URL in params, so the link
    # cannot become an open redirect. The fragment lands the user back on the
    # card they opened.
    class BackLink < Components::Base
      SEARCH = "search"
      FIND_LIST = "find_list"

      # The allow-listed origin as URL params: `{ from: "search", q: }`,
      # `{ from: "find_list" }`, or `{}` for anything else.

      #: (untyped from, untyped query) -> Hash[Symbol, String]
      def self.origin_params(from, query)
        query = query.to_s.strip
        case from.to_s
        when SEARCH then query.empty? ? {} : { from: SEARCH, q: query }
        when FIND_LIST then { from: FIND_LIST }
        else {}
        end
      end

      # The anchor the origin page renders on the item's card or row.

      #: (untyped item) -> String
      def self.search_anchor(item) = "search-result-#{item.id}"

      #: (untyped item) -> String
      def self.find_list_anchor(item) = "find-list-item-#{item.id}"

      #: (move: untyped, item: untyped, ?origin: Hash[Symbol, String]) -> void
      def initialize(move:, item:, origin: {})
        @move = move
        @item = item
        @origin = self.class.origin_params(origin[:from], origin[:q])
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
        case @origin[:from]
        when SEARCH
          [move_search_path(@move, q: @origin[:q], anchor: self.class.search_anchor(@item)),
           I18n.t("items.show.back_to_results")]
        when FIND_LIST
          [move_find_list_path(@move, anchor: self.class.find_list_anchor(@item)),
           I18n.t("items.show.back_to_find_list")]
        else
          [move_box_path(@move, @item.box), I18n.t("items.show.back")]
        end
      end
    end
  end
end
