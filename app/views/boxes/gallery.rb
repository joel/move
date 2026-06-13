# frozen_string_literal: true

module Views
  module Boxes
    # B1 gallery — the box's captured photos (never cropped; Domain §4.9, TF §13).
    # A photo that produced at least one item links to its per-photo review walk
    # (one photo → many items); photos with no items (failed / processing /
    # zero-detection) are absent from that walk, so they render as plain
    # thumbnails to avoid a "Photo 1 of 0" dead end (#162).
    class Gallery < Views::Base
      def initialize(move:, box:, media:, reviewable_media_ids: [])
        @move = move
        @box = box
        @media = media
        @reviewable_media_ids = reviewable_media_ids.to_set
      end

      def view_template
        aside(class: "flex flex-col gap-stack-gap lg:col-span-4") do
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
        @reviewable_media_ids.include?(media.id) ? review_link(media) : plain_thumb(media)
      end

      # turbo_prefetch:"false" (string — a boolean false is dropped by Phlex):
      # ReviewsController#photo marks the photo's unreviewed items reviewed on GET,
      # so a hover prefetch would silently clear pending_review.
      def review_link(media)
        a(
          href: move_box_review_photo_path(@move, @box, media_id: media.id),
          data: { turbo_prefetch: "false" },
          class: "#{tile_classes} group ring-accent-sage hover:ring-2"
        ) { image(media, hover: true) }
      end

      def plain_thumb(media)
        div(class: tile_classes) { image(media) }
      end

      def tile_classes
        "flex aspect-square items-center justify-center overflow-hidden " \
          "rounded-xl bg-surface-container-high text-muted transition"
      end

      def image(media, hover: false)
        if media.image.attached?
          img(
            src: view_context.rails_storage_proxy_path(media.image), alt: "", loading: "lazy",
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
