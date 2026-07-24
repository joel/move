# frozen_string_literal: true

module Components
  module Gallery
    # The gallery's keyset pager (#718): "N more photos" + a Load More form
    # carrying the (captured_at, id) cursor of the last rendered tile plus the
    # active sort/room filter. The infinite-scroll controller (#720) submits
    # the form on its own once it nears the viewport — each replaced pager
    # re-arms the observer, so pages chain until exhaustion; the button is the
    # no-JS / failure fallback. Submitting fetches the next page as a
    # turbo_stream (append tiles + replace this pager with the advanced
    # cursor); without Turbo the same GET renders a full page starting at the
    # cursor. The wrapper div always renders — it is the stable replace target
    # for the final page's stream — but carries no chrome once nothing remains.
    class Pager < Components::Base
      include Phlex::Rails::Helpers::FormWith

      ID = "gallery-pager"

      #: (move: untyped, cursor: untyped, remaining: Integer, sort_key: String, ?selected_room_id: untyped) -> void
      def initialize(move:, cursor:, remaining:, sort_key:, selected_room_id: nil)
        @move = move
        @cursor = cursor
        @remaining = remaining
        @sort_key = sort_key
        @selected_room_id = selected_room_id
      end

      #: () -> void
      def view_template
        div(id: ID, class: "flex flex-col items-center gap-3") do
          body if @cursor && @remaining.positive?
        end
      end

      private

      #: () -> untyped
      def body
        p(class: "text-body-md text-on-surface-variant") do
          I18n.t("galleries.index.pager.remaining", count: @remaining)
        end
        form_with(url: move_gallery_path(@move), method: :get,
                  data: { turbo_stream: true, controller: "infinite-scroll" }) do
          hidden_params
          render Components::Ui::Button.new(
            label: I18n.t("galleries.index.pager.load_more"),
            type: "submit", variant: :secondary,
            data: { turbo_submits_with: I18n.t("galleries.index.pager.loading") }
          )
        end
      end

      # iso8601(6): captured_at is timestamp(6); whole-second precision would
      # move the cursor off the real boundary and skip rows (the #194 lesson).

      #: () -> untyped
      def hidden_params
        input(type: "hidden", name: "sort", value: @sort_key) unless @sort_key == "recent"
        input(type: "hidden", name: "room_id", value: @selected_room_id) if @selected_room_id
        input(type: "hidden", name: "cursor", value: @cursor.captured_at.iso8601(6))
        input(type: "hidden", name: "cursor_id", value: @cursor.id)
      end
    end
  end
end
