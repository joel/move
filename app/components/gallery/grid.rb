# frozen_string_literal: true

module Components
  module Gallery
    # The Move-wide photo grid + its lightbox. Mirrors the box ContentsGrid tile
    # (square :thumb, lazy-loaded, group-hover zoom) but every tile is a button
    # that opens a single shared <dialog> lightbox driven by the `lightbox`
    # Stimulus controller. Each tile carries its :thumb/:detail srcs, a caption
    # and a "view box" href as data-*; the controller renders them thumb-first
    # into a 3-slide draggable track (prev/current/next, wrapping) so navigation
    # is instant and neighbours preload. Swipe, arrows (fine pointers only) and
    # arrow keys all turn the page. Read-only — no mutating affordances.
    class Grid < Components::Base
      #: (move: untyped, media: untyped) -> void
      def initialize(move:, media:)
        @move = move
        @media = media
      end

      #: () -> void
      def view_template
        # turbo:before-cache closes the viewer — Turbo would otherwise snapshot
        # the page with an open <dialog> (modal top-layer state isn't restorable)
        # and a mutated, possibly expired img src.
        div(data: { controller: "lightbox", action: "turbo:before-cache@document->lightbox#close" }) do
          grid
          lightbox
        end
      end

      private

      #: () -> untyped
      def grid
        div(class: "grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4") do
          @media.each { |media| tile(media) }
        end
      end

      #: (untyped media) -> untyped
      def tile(media)
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
          tile_body(media)
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

      #: (untyped media) -> untyped
      def tile_body(media)
        div(class: image_tile_classes) do
          image(media)
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

      #: (untyped media) -> untyped
      def image(media)
        if media.image_displayable?
          img(
            src: thumb_url(media), alt: "", loading: "lazy",
            class: "h-full w-full object-cover transition group-hover:scale-105"
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
        }
      end

      # Memoized so the grid <img src> and data-thumb are byte-identical: every
      # TransformUrl call embeds a fresh signed expiry, so a second call can
      # yield a different query string — and the lightbox's "already cached"
      # instant thumb would silently become a fresh network fetch.

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

      # The single shared viewer. Hidden until a tile opens it. The inner wrapper is
      # the backdrop (click-to-close); the track is pointer-events-none (images opt
      # back in), so clicks on empty slide area reach the wrapper and close, while
      # clicks on the photo or the controls do not.
      #
      # Touch handlers live on the dialog so a drag can start anywhere in the
      # viewer; all passive — the drag never calls preventDefault (Phlex forbids
      # inline on* handlers by design, so this is Stimulus data-action anyway).

      #: () -> untyped
      def lightbox
        dialog(
          class: "ha-lightbox",
          data: {
            lightbox_target: "dialog",
            action: "keydown->lightbox#key close->lightbox#closed " \
                    "touchstart->lightbox#touchStart:passive " \
                    "touchmove->lightbox#touchMove:passive touchend->lightbox#touchEnd:passive " \
                    "touchcancel->lightbox#touchCancel:passive"
          }
        ) do
          div(
            class: "relative flex h-full w-full items-center justify-center overflow-hidden p-4",
            data: { action: "click->lightbox#backdropClose" }
          ) do
            top_bar
            nav_button(:prev, "left-2", "rotate-180")
            track
            nav_button(:next, "right-2", "")
          end
        end
      end

      # The 3-slide draggable strip: prev / current / next photos as real <img>s
      # (so neighbours preload), recentred by the controller after each turn.

      #: () -> untyped
      def track
        div(
          class: "ha-lightbox-track pointer-events-none flex h-full w-full",
          data: { lightbox_target: "track" }
        ) do
          3.times { slide }
        end
      end

      # aria-hidden by default: the controller exposes only the centre slide to
      # assistive tech (the neighbours are visual preloads).

      #: () -> untyped
      def slide
        div(class: "flex h-full w-full shrink-0 items-center justify-center") do
          img(
            data: { lightbox_target: "slide" }, alt: "", aria_hidden: "true",
            class: "pointer-events-auto max-h-[88dvh] max-w-[92vw] rounded-card object-contain shadow-lg"
          )
        end
      end

      #: () -> untyped
      def top_bar
        div(class: "absolute inset-x-0 top-0 z-10 flex items-center justify-between gap-3 p-4") do
          span(
            data: { lightbox_target: "caption" },
            class: "truncate rounded-full bg-page/70 px-3 py-1 text-label-caps uppercase " \
                   "text-text-warm backdrop-blur"
          )
          div(class: "flex items-center gap-2") do
            a(
              data: { lightbox_target: "link" },
              class: "rounded-full bg-page/70 px-3 py-1 text-label-caps uppercase text-text-warm " \
                     "backdrop-blur transition hover:bg-page"
            ) { I18n.t("galleries.index.lightbox.view_box") }
            close_button
          end
        end
      end

      #: () -> untyped
      def close_button
        button(
          type: "button", aria_label: I18n.t("galleries.index.lightbox.close"),
          data: { action: "lightbox#close" },
          class: "flex h-8 w-8 items-center justify-center rounded-full bg-page/70 text-text-warm " \
                 "backdrop-blur transition hover:bg-page"
        ) { render Components::Icons::Close.new(css: "h-5 w-5") }
      end

      # Rendered only when SOME fine pointer exists (any-pointer, not the primary
      # pointer — a tablet with a mouse attached still gets arrows); on pure touch
      # screens the swipe is the affordance. Keyboard arrows work regardless.

      #: (untyped direction, untyped side, untyped rotate) -> untyped
      def nav_button(direction, side, rotate)
        button(
          type: "button", aria_label: I18n.t("galleries.index.lightbox.#{direction}"),
          data: { action: "lightbox##{direction}" },
          class: "absolute #{side} top-1/2 z-10 hidden h-11 w-11 -translate-y-1/2 items-center " \
                 "justify-center rounded-full bg-page/70 text-text-warm backdrop-blur " \
                 "transition any-pointer-fine:flex hover:bg-page"
        ) { render Components::Icons::ChevronRight.new(css: "h-6 w-6 #{rotate}") }
      end
    end
  end
end
