# frozen_string_literal: true

module Views
  module Boxes
    # B1 gallery — the box's captured photos (never cropped; Domain §4.9, TF §13).
    # A photo that produced at least one item links to its per-photo review walk
    # (one photo → many items). A photo with no item but a *settled* recognition
    # attempt (failed / zero-detection) links to the recovery screen so it isn't a
    # dead end. Photos still queued/processing render as plain thumbnails — they're
    # transient and never enter the review walk (the "Photo 1 of 0" guard, #162).
    class Gallery < Views::Base
      def initialize(move:, box:, media:, reviewable_media_ids: [], recoverable_media_ids: [],
                     unpacked_media_ids: [])
        @move = move
        @box = box
        @media = media
        @reviewable_media_ids = reviewable_media_ids.to_set
        @recoverable_media_ids = recoverable_media_ids.to_set
        # Photos whose every sourced item has been unpacked (destination side) —
        # badged so the gallery reflects unpacking progress (empty while packing).
        @unpacked_media_ids = unpacked_media_ids.to_set
      end

      def view_template
        aside(class: "flex flex-col gap-stack-gap") do
          div(class: "flex items-center justify-between px-2") do
            h3(class: "text-headline-md text-text-warm") { I18n.t("boxes.show.gallery") }
            span(class: "text-label-caps uppercase text-muted") do
              I18n.t("boxes.show.photos", count: @media.size)
            end
          end
          @media.any? ? grid : empty
        end
      end

      private

      def grid
        div(class: "grid grid-cols-2 gap-3") do
          @media.each { |media| thumb(media) }
        end
      end

      def thumb(media)
        if @reviewable_media_ids.include?(media.id)
          review_link(media)
        elsif @recoverable_media_ids.include?(media.id)
          recovery_link(media)
        else
          plain_thumb(media)
        end
      end

      # An orphaned-but-settled photo: tappable, with a terracotta alert marker so
      # the user can tell it needs attention. Goes to the recovery screen, NOT the
      # review walk (respects #162 — it never produced an item to walk).
      def recovery_link(media)
        a(
          href: move_box_recovery_photo_path(@move, @box, media_id: media.id),
          class: "#{tile_classes} group ring-error/40 hover:ring-2"
        ) do
          image(media, hover: true)
          span(class: "absolute right-1.5 top-1.5 flex h-6 w-6 items-center justify-center " \
                      "rounded-full bg-error/90 text-on-error") do
            render Components::Icons::Alert.new(css: "h-3.5 w-3.5")
          end
          unpacked_badge(media)
        end
      end

      # turbo_prefetch:"false" (string — a boolean false is dropped by Phlex):
      # ReviewsController#photo marks the photo's unreviewed items reviewed on GET,
      # so a hover prefetch would silently clear pending_review.
      def review_link(media)
        a(
          href: move_box_review_photo_path(@move, @box, media_id: media.id),
          data: { turbo_prefetch: "false" },
          class: "#{tile_classes} group ring-accent-sage hover:ring-2"
        ) do
          image(media, hover: true)
          unpacked_badge(media)
        end
      end

      def plain_thumb(media)
        div(class: tile_classes) do
          image(media)
          unpacked_badge(media)
        end
      end

      # Destination-side badge: every item this photo sourced has been unpacked.
      # A sage check, top-left so it never collides with the recovery alert marker
      # (top-right) — and the two are mutually exclusive anyway (a recoverable photo
      # has no item; an unpacked one does).
      def unpacked_badge(media)
        return unless @unpacked_media_ids.include?(media.id)

        span(class: "absolute left-1.5 top-1.5 z-10 inline-flex items-center gap-1 rounded-full " \
                    "bg-accent-sage/90 px-2 py-0.5 text-label-caps uppercase text-page") do
          render Components::Icons::Check.new(css: "h-3 w-3")
          plain I18n.t("boxes.gallery.unpacked")
        end
      end

      def tile_classes
        "relative flex aspect-square items-center justify-center overflow-hidden " \
          "rounded-xl bg-surface-container-high text-muted transition"
      end

      def image(media, hover: false)
        if media.image.attached?
          img(
            src: view_context.rails_storage_proxy_path(media.image.variant(:thumb)), alt: "", loading: "lazy",
            class: "h-full w-full object-cover#{" transition group-hover:scale-105" if hover}"
          )
        else
          render Components::Icons::Camera.new(css: "h-7 w-7")
        end
      end

      def empty
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Camera,
          title: I18n.t("boxes.show.gallery_empty_title"),
          description: I18n.t("boxes.show.gallery_empty_description")
        )
      end
    end
  end
end
