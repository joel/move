# frozen_string_literal: true

module Components
  module ReviewQueue
    # The review queue's photo grid (#654). Mirrors the Gallery tile anatomy
    # (square :thumb, lazy-loaded, caption strip) but each tile is a plain link
    # into the C2 review screen in queue mode — no lightbox — wearing a pending
    # item count badge in the app-wide pending-review tint (BoxReviewBadge).
    # Opening a review photo confirms its items (a GET-side effect), so every
    # tile disables Turbo prefetch: hovering must not review a photo.
    class Grid < Components::Base
      #: (move: untyped, media: untyped, pending_counts: untyped) -> void
      def initialize(move:, media:, pending_counts:)
        @move = move
        @media = media
        @pending_counts = pending_counts
      end

      #: () -> void
      def view_template
        div(class: "grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4") do
          @media.each { |media| tile(media) }
        end
      end

      private

      #: (untyped media) -> untyped
      def tile(media)
        a(
          href: move_box_review_photo_path(@move, media.box, media, queue: "move"),
          aria_label: caption(media),
          data: { turbo_prefetch: "false" },
          class: "group flex flex-col overflow-hidden rounded-card border border-card-border " \
                 "bg-card text-left transition hover:border-accent-sage focus:outline-none " \
                 "focus:ring-2 focus:ring-accent-sage/40"
        ) do
          div(class: "relative flex aspect-square items-center justify-center overflow-hidden " \
                     "bg-surface-container-high text-muted") do
            image(media)
            count_badge(media)
          end
          caption_strip(media)
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

      # How many items opening this photo will confirm — the queue's unit of work.

      #: (untyped media) -> untyped
      def count_badge(media)
        span(class: "absolute right-1.5 top-1.5 z-10 rounded-full bg-tertiary/15 px-2 py-0.5 " \
                    "text-label-caps uppercase text-tertiary backdrop-blur") do
          I18n.t("review_queues.show.pending_badge", count: @pending_counts.fetch(media.id, 0))
        end
      end

      #: (untyped media) -> untyped
      def caption_strip(media)
        span(class: "block truncate px-3 py-2 text-label-caps uppercase text-on-surface-variant") do
          caption(media)
        end
      end

      #: (untyped media) -> String?
      def thumb_url(media)
        MediaVariants::TransformUrl.for(media, :thumb)
      end

      # "Box 3 · Kitchen" — the photo's location; box and room are eager-loaded
      # by the controller.

      #: (untyped media) -> untyped
      def caption(media)
        parts = [I18n.t("review_queues.show.box_label", number: media.box.number)]
        parts << media.box.room.name if media.box.room
        parts.join(" · ")
      end
    end
  end
end
