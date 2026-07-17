# frozen_string_literal: true

module Views
  module Recoveries
    # Photo recovery screen for an orphaned photo (recognition failed / found
    # nothing). A state-variant of the C2 review/photo layout (same split: image
    # left, action card right) — see doc/phases/DESIGN-DISCREPANCIES.md. The right
    # card is the live status region (Recoveries::State) wrapped in the recognition
    # poller so a re-run's progress updates in place. Renders in AppShellLayout.
    class Show < Views::Base
      #: (move: untyped, box: untyped, media: untyped, run: untyped, ?editable: untyped) -> void
      def initialize(move:, box:, media:, run:, editable: false)
        @move = move
        @box = box
        @media = media
        @run = run
        @editable = editable
      end

      #: () -> void
      def view_template
        back_link
        div(class: "grid grid-cols-1 gap-stack-gap lg:grid-cols-12") do
          media_panel
          panel
        end
      end

      private

      #: () -> untyped
      def back_link
        a(
          href: move_box_path(@move, @box),
          class: "inline-flex items-center gap-2 text-label-caps uppercase text-muted hover:text-text-warm"
        ) do
          render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-180")
          plain I18n.t("recoveries.back")
        end
      end

      #: () -> untyped
      def media_panel
        section(class: "mt-stack-gap lg:col-span-7") do
          div(class: "relative overflow-hidden rounded-card border border-card-border bg-surface-container-high") do
            badge
            if @media.image_displayable?
              # The page's LCP element — eager + high priority, never lazy (#673).
              img(src: MediaVariants::TransformUrl.for(@media, :detail),
                  class: "aspect-square w-full object-cover lg:aspect-auto lg:h-full", alt: "",
                  fetchpriority: "high", decoding: "async")
            elsif @media.image_unavailable?
              div(class: "flex aspect-square w-full flex-col items-center justify-center gap-2 text-muted") do
                render Components::Icons::ImageOff.new(css: "h-10 w-10")
                span(class: "text-body-md") { I18n.t("ui.media.unavailable") }
              end
            else
              div(class: "flex aspect-square w-full items-center justify-center text-muted") do
                render Components::Icons::Camera.new(css: "h-10 w-10")
              end
            end
          end
        end
      end

      #: () -> untyped
      def badge
        div(class: "absolute left-3 top-3 z-10 inline-flex items-center gap-2 rounded-full " \
                   "bg-surface-container-high/80 px-3 py-1 text-label-caps uppercase text-on-surface-variant " \
                   "backdrop-blur") do
          render Components::Icons::Camera.new(css: "h-3.5 w-3.5 text-accent-sage")
          plain I18n.t("recoveries.badge")
        end
      end

      #: () -> untyped
      def panel
        section(class: "mt-stack-gap lg:col-span-5") do
          div(
            data: {
              controller: "recognition-poller",
              recognition_poller_url_value: move_box_recovery_photo_state_path(@move, @box, @media),
              recognition_poller_interval_value: 2500
            }
          ) do
            div(data: { recognition_poller_target: "frame" }) do
              render Views::Recoveries::State.new(
                move: @move, box: @box, media: @media, run: @run, editable: @editable, recovered: false
              )
            end
          end
        end
      end
    end
  end
end
