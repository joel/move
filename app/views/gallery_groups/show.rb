# frozen_string_literal: true

module Views
  module GalleryGroups
    # One item family in full (#633) — an unpacking checklist, not a gallery:
    # member rows ordered by box number so you sweep one box at a time, each
    # row locating itself with the same "Box N · Room" chip the group card
    # taught. Tapping the chip (or row) goes to the box.
    class Show < Views::Base
      #: (move: untyped, cluster: untyped, members: untyped) -> void
      def initialize(move:, cluster:, members:)
        @move = move
        @cluster = cluster
        @members = members
      end

      #: () -> void
      def view_template
        div(class: "flex flex-col gap-section-gap") do
          header
          back_link
          @members.any? ? member_list : empty_state
        end
      end

      private

      #: () -> untyped
      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: @move.name,
          title: @cluster.label,
          subtitle: subtitle
        )
      end

      #: () -> String
      def subtitle
        [
          I18n.t("galleries.groups.card.items", count: @cluster.items_count),
          I18n.t("galleries.groups.card.boxes", count: @cluster.boxes_count)
        ].join(" · ")
      end

      #: () -> untyped
      def back_link
        a(
          href: move_gallery_path(@move, view: "groups"),
          class: "text-label-caps uppercase text-on-surface-variant transition hover:text-accent-sage"
        ) { I18n.t("gallery_groups.show.back") }
      end

      #: () -> untyped
      def member_list
        ul(class: "flex flex-col gap-2") do
          @members.each { |item| member_row(item) }
        end
      end

      #: (untyped item) -> untyped
      def member_row(item)
        li do
          a(
            href: move_box_path(@move, item.box),
            class: "flex items-center gap-3 rounded-card border border-card-border bg-card p-3 " \
                   "transition hover:border-accent-sage focus:outline-none " \
                   "focus:ring-2 focus:ring-accent-sage/40"
          ) do
            member_thumb(item)
            span(class: "min-w-0 flex-1 truncate text-body-md text-text-warm") { item.name }
            render Components::Ui::Chip.new(label: location(item), kind: :category)
          end
        end
      end

      #: (untyped item) -> untyped
      def member_thumb(item)
        div(class: "flex h-12 w-12 flex-shrink-0 items-center justify-center overflow-hidden " \
                   "rounded-lg bg-surface-container-high text-muted") do
          media = item.source_media
          if media&.image_displayable?
            img(src: thumb_url(media), alt: "", loading: "lazy", class: "h-full w-full object-cover")
          else
            render Components::Icons::Camera.new(css: "h-5 w-5 opacity-40")
          end
        end
      end

      # "Box 3 · Kitchen" — the member's locator, same vocabulary as the card.

      #: (untyped item) -> String
      def location(item)
        parts = [I18n.t("gallery_groups.show.box_label", number: item.box.number)]
        parts << item.box.room.name if item.box.room
        parts.join(" · ")
      end

      # Every member vanished between recomputes (all removed/discarded) — the
      # counts will catch up at the next recompute; direct honestly meanwhile.

      #: () -> untyped
      def empty_state
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Sparkles,
          title: I18n.t("gallery_groups.show.empty.title"),
          description: I18n.t("gallery_groups.show.empty.description")
        )
      end

      #: (untyped media) -> String?
      def thumb_url(media)
        (@thumb_urls ||= {})[media.id] ||= MediaVariants::TransformUrl.for(media, :thumb)
      end
    end
  end
end
