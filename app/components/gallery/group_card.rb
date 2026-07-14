# frozen_string_literal: true

module Components
  module Gallery
    # One item family (#633): a 2×2 quilt of member photos in the gallery
    # tiles' visual language, the family's name and size, and the signature —
    # a row of box-number chips. The chips aren't decoration: they ARE the
    # retrieval answer ("your batteries are in boxes 3, 7 and 12"), and the
    # same chip vocabulary locates each member on the detail page.
    class GroupCard < Components::Base
      CHIP_CAP = 3

      #: (move: untyped, cluster: untyped, previews: untyped, box_numbers: untyped) -> void
      def initialize(move:, cluster:, previews:, box_numbers:)
        @move = move
        @cluster = cluster
        @previews = previews
        @box_numbers = box_numbers
      end

      #: () -> void
      def view_template
        a(
          href: move_gallery_group_path(@move, @cluster),
          aria_label: aria_label,
          class: "group flex flex-col gap-3 rounded-card border border-card-border bg-card p-3 " \
                 "transition hover:border-accent-sage focus:outline-none " \
                 "focus:ring-2 focus:ring-accent-sage/40"
        ) do
          quilt
          div(class: "flex flex-col gap-2") do
            title_line
            chips
          end
        end
      end

      private

      #: () -> untyped
      def quilt
        div(class: "grid grid-cols-2 gap-1 overflow-hidden rounded-lg") do
          4.times { |slot| quilt_cell(@previews[slot]) }
        end
      end

      #: (untyped media) -> untyped
      def quilt_cell(media)
        div(class: "relative flex aspect-square items-center justify-center overflow-hidden " \
                   "bg-surface-container-high text-muted") do
          if media
            img(
              src: thumb_url(media), alt: "", loading: "lazy",
              class: "h-full w-full object-cover transition group-hover:scale-105"
            )
          else
            render Components::Icons::Camera.new(css: "h-5 w-5 opacity-40")
          end
        end
      end

      #: () -> untyped
      def title_line
        p(class: "truncate text-title-md text-text-warm") { @cluster.label }
        p(class: "text-label-caps uppercase text-on-surface-variant") { counts }
      end

      # "9 items · 4 boxes" — the size; the chips below carry the WHERE.

      #: () -> String
      def counts
        [
          I18n.t("galleries.groups.card.items", count: @cluster.items_count),
          I18n.t("galleries.groups.card.boxes", count: @cluster.boxes_count)
        ].join(" · ")
      end

      #: () -> untyped
      def chips
        div(class: "flex flex-wrap gap-2") do
          @box_numbers.first(CHIP_CAP).each do |number|
            render Components::Ui::Chip.new(
              label: I18n.t("galleries.groups.card.box_chip", number: number), kind: :category
            )
          end
          overflow_chip
        end
      end

      #: () -> untyped
      def overflow_chip
        hidden = @box_numbers.size - CHIP_CAP
        return unless hidden.positive?

        render Components::Ui::Chip.new(
          label: I18n.t("galleries.groups.card.more_boxes", count: hidden), kind: :category
        )
      end

      #: () -> String
      def aria_label
        "#{@cluster.label} — #{counts}"
      end

      # Memoized for byte-identical URLs within one render (TransformUrl embeds
      # a fresh signed expiry per call — the gallery grid's idiom).

      #: (untyped media) -> String?
      def thumb_url(media)
        (@thumb_urls ||= {})[media.id] ||= MediaVariants::TransformUrl.for(media, :thumb)
      end
    end
  end
end
