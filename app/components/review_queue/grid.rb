# frozen_string_literal: true

module Components
  module ReviewQueue
    # The review queue's photo grid (#654). Mirrors the Gallery tile anatomy
    # (square :thumb, lazy-loaded, caption strip) but each tile is a plain link
    # into the C2 review screen in queue mode — no lightbox — wearing a pending
    # item count badge in the app-wide pending-review tint (BoxReviewBadge).
    class Grid < Components::Base
      #: (move: untyped, media: untyped, pending_counts: untyped) -> void
      def initialize(move:, media:, pending_counts:)
        @move = move
        @media = media
        @pending_counts = pending_counts
      end

      # Above-the-fold tiles load eagerly — one lg row / two mobile rows (#673).
      EAGER_TILES = 4

      #: () -> void
      def view_template
        div(class: "grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4") do
          @media.each_with_index { |media, index| tile(media, eager: index < EAGER_TILES) }
        end
      end

      private

      #: (untyped media, eager: bool) -> untyped
      def tile(media, eager:)
        a(
          href: move_box_review_photo_path(@move, media.box, media, queue: "move"),
          aria_label: caption(media),
          class: "group flex flex-col overflow-hidden rounded-card border border-card-border " \
                 "bg-card text-left transition hover:border-accent-sage focus:outline-none " \
                 "focus:ring-2 focus:ring-accent-sage/40"
        ) do
          div(class: "relative flex aspect-square items-center justify-center overflow-hidden " \
                     "bg-surface-container-high text-muted") do
            image(media, eager:)
            count_badge(media)
          end
          caption_strip(media)
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
