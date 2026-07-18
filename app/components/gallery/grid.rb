# frozen_string_literal: true

module Components
  module Gallery
    # The Move-wide photo grid + its lightbox. Mirrors the box ContentsGrid tile
    # (square :thumb, lazy-loaded, group-hover zoom) but every tile is a button
    # that opens a PhotoSwipe viewer driven by the `lightbox` Stimulus wrapper
    # (vendored PhotoSwipe 5 — swipe physics, pinch/double-tap zoom, preloading,
    # keyboard, focus trap). Each tile carries its :thumb/:detail srcs, a
    # caption and a "view box" href as data-*; PhotoSwipe injects its own DOM at
    # open, seeded thumb-first via msrc. Read-only — no mutating affordances.
    class Grid < Components::Base
      # The lightbox slide box — mirrors the Worker's :detail geometry so the
      # data-pswp-* contract stays "the served detail size".
      DETAIL_BOX = MediaVariants::TransformUrl::SIZES.fetch(:detail).fetch(:width)

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
          grid
        end
      end

      # Above-the-fold tiles load eagerly — one desktop row (lg:grid-cols-4) /
      # two mobile rows (grid-cols-2); lazy-loading the likely-LCP first row
      # would deprioritize the first visible pixels (#673). The rest stay lazy.
      EAGER_TILES = 4

      private

      #: () -> untyped
      def grid
        div(class: "grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4") do
          @media.each_with_index { |media, index| tile(media, eager: index < EAGER_TILES) }
        end
      end

      #: (untyped media, eager: bool) -> untyped
      def tile(media, eager:)
        # An unavailable photo (#563) has nothing to enlarge — render an inert
        # tile so a tap doesn't open a blank lightbox (its detail_src is nil).
        return static_tile(media) unless media.image_displayable?

        button(
          type: "button",
          aria_label: caption(media),
          data: tile_data(media),
          class: "group flex flex-col overflow-hidden rounded-card border border-card-border " \
                 "bg-card text-left transition hover:border-accent-sage focus:outline-none " \
                 "focus:ring-2 focus:ring-accent-sage/40"
        ) do
          tile_body(media, eager:)
        end
      end

      #: (untyped media) -> untyped
      def static_tile(media)
        div(
          aria_label: caption(media),
          class: "group flex flex-col overflow-hidden rounded-card border border-card-border bg-card text-left"
        ) do
          tile_body(media)
        end
      end

      #: (untyped media, ?eager: bool) -> untyped
      def tile_body(media, eager: false)
        div(class: image_tile_classes) do
          image(media, eager:)
          generated_badge if generated?(media)
        end
        caption_strip(media)
      end

      #: () -> String
      def image_tile_classes
        "relative flex aspect-square items-center justify-center overflow-hidden " \
          "bg-surface-container-high text-muted"
      end

      # The photo's location, shown beneath the image so the box/room is legible
      # while browsing across boxes (not only on hover/tap).

      #: (untyped media) -> untyped
      def caption_strip(media)
        span(class: "block truncate px-3 py-2 text-label-caps uppercase text-on-surface-variant") do
          caption(media)
        end
      end

      #: (untyped media, ?eager: bool) -> untyped
      def image(media, eager: false)
        if media.image_displayable?
          render Components::Ui::BlurUpImage.new(
            src: thumb_url(media), lqip: media.image_lqip,
            loading: eager ? "eager" : "lazy", decoding: "async",
            img_class: "h-full w-full object-cover transition group-hover:scale-105"
          )
        elsif media.image_unavailable?
          render Components::Icons::ImageOff.new(css: "h-7 w-7")
        else
          render Components::Icons::Camera.new(css: "h-7 w-7")
        end
      end

      #: () -> untyped
      def generated_badge
        span(class: "absolute left-1.5 top-1.5 z-10 inline-flex items-center gap-1 rounded-full " \
                    "bg-page/80 px-2 py-0.5 text-label-caps uppercase text-text-warm backdrop-blur") do
          render Components::Icons::Sparkles.new(css: "h-3 w-3")
          plain I18n.t("galleries.index.generated")
        end
      end

      #: (untyped media) -> untyped
      def tile_data(media)
        {
          lightbox_target: "tile",
          action: "click->lightbox#open",
          src: detail_src(media),
          thumb: thumb_url(media),
          caption: caption(media),
          href: move_box_path(@move, media.box)
        }.merge(pswp_dimensions(media))
      end

      # Real slide dimensions when blob analysis has them. The dataset contract
      # is "the SERVED detail size" (the viewer reads data-pswp-* first —
      # photoswipe_viewer.js#dimensionsFor — and corrects any mismatch with a
      # slide refresh): behind the edge Worker that is the master scaled into
      # the :detail box, clamped at 1.0 to mirror scale-down (never upscaled);
      # the dev/test fallback proxies the UNRESIZED master, so emit the raw
      # dimensions there or the correction reflow returns (#676 Codex). Omitted
      # while a blob is unanalyzed — the JS falls back to its estimate (#675).

      #: (untyped media) -> Hash[Symbol, Integer]
      def pswp_dimensions(media)
        meta = media.image.blob.metadata
        width = meta["width"].to_i
        height = meta["height"].to_i
        return {} unless width.positive? && height.positive?
        return { pswp_width: width, pswp_height: height } unless edge_transforms?

        scale = [DETAIL_BOX.to_f / width, DETAIL_BOX.to_f / height, 1.0].min
        { pswp_width: (width * scale).round, pswp_height: (height * scale).round }
      end

      #: () -> bool
      def edge_transforms?
        Rails.application.config.x.media_transform_host.present?
      end

      # Memoized so the grid <img src> and data-thumb are byte-identical even if
      # TransformUrl's expiry bucket rolls over mid-render (#669 quantized the
      # expiry, so calls normally repeat within a bucket) — a divergent query
      # string would turn the lightbox's "already cached" instant thumb into a
      # fresh network fetch. Also saves an HMAC per repeated call.

      #: (untyped media) -> String?
      def thumb_url(media)
        (@thumb_urls ||= {})[media.id] ||= MediaVariants::TransformUrl.for(media, :thumb)
      end

      #: (untyped media) -> untyped
      def detail_src(media)
        MediaVariants::TransformUrl.for(media, :detail) # nil for a non-displayable photo
      end

      #: (untyped media) -> untyped
      def generated?(media)
        media.captured_via == "generated"
      end

      # "Box 3 · Kitchen" — the photo's location, used as the tile aria-label and
      # the lightbox caption. Box and room are eager-loaded by the controller.

      #: (untyped media) -> untyped
      def caption(media)
        parts = [I18n.t("galleries.index.box_label", number: media.box.number)]
        parts << media.box.room.name if media.box.room
        parts.join(" · ")
      end

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
