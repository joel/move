# frozen_string_literal: true

module Components
  module Gallery
    # The Move-wide photo grid + its lightbox. Mirrors the box ContentsGrid tile
    # (square :thumb, lazy-loaded, group-hover zoom) but every tile is a button
    # that opens a single shared <dialog> lightbox driven by the `lightbox`
    # Stimulus controller. Each tile carries the :detail src, a caption and a
    # "view box" href as data-*; the controller swaps them in on open and cycles
    # prev/next over the rendered set. Read-only — no mutating affordances.
    class Grid < Components::Base
      def initialize(move:, media:)
        @move = move
        @media = media
      end

      def view_template
        div(data: { controller: "lightbox" }) do
          grid
          lightbox
        end
      end

      private

      def grid
        div(class: "grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4") do
          @media.each { |media| tile(media) }
        end
      end

      def tile(media)
        button(
          type: "button",
          aria_label: caption(media),
          data: tile_data(media),
          class: "group relative flex aspect-square items-center justify-center overflow-hidden " \
                 "rounded-card border border-card-border bg-surface-container-high text-muted " \
                 "transition hover:border-accent-sage focus:outline-none " \
                 "focus:ring-2 focus:ring-accent-sage/40"
        ) do
          image(media)
          generated_badge if generated?(media)
        end
      end

      def image(media)
        if media.image.attached?
          img(
            src: view_context.rails_storage_proxy_path(media.image.variant(:thumb)), alt: "", loading: "lazy",
            class: "h-full w-full object-cover transition group-hover:scale-105"
          )
        else
          render Components::Icons::Camera.new(css: "h-7 w-7")
        end
      end

      def generated_badge
        span(class: "absolute left-1.5 top-1.5 z-10 inline-flex items-center gap-1 rounded-full " \
                    "bg-page/80 px-2 py-0.5 text-label-caps uppercase text-text-warm backdrop-blur") do
          render Components::Icons::Sparkles.new(css: "h-3 w-3")
          plain I18n.t("galleries.index.generated")
        end
      end

      def tile_data(media)
        {
          lightbox_target: "tile",
          action: "click->lightbox#open",
          src: detail_src(media),
          caption: caption(media),
          href: move_box_path(@move, media.box)
        }
      end

      def detail_src(media)
        return unless media.image.attached?

        view_context.rails_storage_proxy_path(media.image.variant(:detail))
      end

      def generated?(media)
        media.captured_via == "generated"
      end

      # "Box 3 · Kitchen" — the photo's location, used as the tile aria-label and
      # the lightbox caption. Box and room are eager-loaded by the controller.
      def caption(media)
        parts = [I18n.t("galleries.index.box_label", number: media.box.number)]
        parts << media.box.room.name if media.box.room
        parts.join(" · ")
      end

      # The single shared viewer. Hidden until a tile opens it. The inner wrapper is
      # the backdrop (click-to-close); the image and controls are children, so a
      # click on them does not close.
      def lightbox
        dialog(
          class: "ha-lightbox",
          data: { lightbox_target: "dialog", action: "keydown->lightbox#key" }
        ) do
          div(
            class: "relative flex h-full w-full items-center justify-center p-4",
            data: { action: "click->lightbox#backdropClose" }
          ) do
            top_bar
            nav_button(:prev, "left-2", "rotate-180")
            img(
              data: { lightbox_target: "image" }, alt: "",
              class: "max-h-[88dvh] max-w-[92vw] rounded-card object-contain shadow-lg"
            )
            nav_button(:next, "right-2", "")
          end
        end
      end

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

      def close_button
        button(
          type: "button", aria_label: I18n.t("galleries.index.lightbox.close"),
          data: { action: "lightbox#close" },
          class: "flex h-8 w-8 items-center justify-center rounded-full bg-page/70 text-text-warm " \
                 "backdrop-blur transition hover:bg-page"
        ) { render Components::Icons::Close.new(css: "h-5 w-5") }
      end

      def nav_button(direction, side, rotate)
        button(
          type: "button", aria_label: I18n.t("galleries.index.lightbox.#{direction}"),
          data: { action: "lightbox##{direction}" },
          class: "absolute #{side} top-1/2 z-10 flex h-11 w-11 -translate-y-1/2 items-center " \
                 "justify-center rounded-full bg-page/70 text-text-warm backdrop-blur " \
                 "transition hover:bg-page"
        ) { render Components::Icons::ChevronRight.new(css: "h-6 w-6 #{rotate}") }
      end
    end
  end
end
