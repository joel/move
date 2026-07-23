# frozen_string_literal: true

module Components
  module Gallery
    # The Move-wide photo grid + its lightbox. Mirrors the box ContentsGrid tile
    # (square :thumb, lazy-loaded, group-hover zoom) but every tile is a button
    # that opens a PhotoSwipe viewer driven by the `lightbox` Stimulus wrapper
    # (vendored PhotoSwipe 5 — swipe physics, pinch/double-tap zoom, preloading,
    # keyboard, focus trap). Tile rendering lives in Gallery::Tiles so the
    # "Load more" turbo_stream can append later pages into the tiles container
    # (#718) — inside this component's lightbox controller subtree, so appended
    # tiles are discovered live at the next open. Read-only — no mutating
    # affordances.
    class Grid < Components::Base
      # The stable append target for later pages. Must stay inside the
      # data-controller="lightbox" element, or appended tiles would fall outside
      # the Stimulus scope and open nothing.
      TILES_ID = "gallery-tiles"

      # Above-the-fold tiles load eagerly — one desktop row (lg:grid-cols-4) /
      # two mobile rows (grid-cols-2); lazy-loading the likely-LCP first row
      # would deprioritize the first visible pixels (#673). The rest stay lazy.
      EAGER_TILES = 4

      #: (move: untyped, media: untyped) -> void
      def initialize(move:, media:)
        @move = move
        @media = media
      end

      #: () -> void
      def view_template
        # turbo:before-cache tears the viewer down — Turbo must never snapshot
        # PhotoSwipe's body-appended DOM.
        div(
          data: {
            controller: "lightbox",
            action: "turbo:before-cache@document->lightbox#teardown",
            lightbox_labels_value: labels.to_json
          }
        ) do
          div(id: TILES_ID, class: "grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4") do
            render Components::Gallery::Tiles.new(move: @move, media: @media, eager_tiles: EAGER_TILES)
          end
        end
      end

      private

      # PhotoSwipe's chrome labels (its buttons + the custom caption/"view box"
      # elements), passed to the Stimulus wrapper as a JSON value.

      #: () -> Hash[Symbol, String]
      def labels
        {
          prev: I18n.t("galleries.index.lightbox.prev"),
          next: I18n.t("galleries.index.lightbox.next"),
          close: I18n.t("galleries.index.lightbox.close"),
          zoom: I18n.t("galleries.index.lightbox.zoom"),
          error: I18n.t("galleries.index.lightbox.error"),
          viewBox: I18n.t("galleries.index.lightbox.view_box"),
          dialog: I18n.t("galleries.index.lightbox.dialog"),
          counter: I18n.t("galleries.index.lightbox.counter")
        }
      end
    end
  end
end
