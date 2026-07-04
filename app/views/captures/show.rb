# frozen_string_literal: true

module Views
  module Captures
    # B2 — Capture image. Target box is always unambiguous in the header. Upload
    # is online-only (server-side via Active Storage); the session panel polls for
    # live recognition state. Renders in the AppShellLayout.
    class Show < Views::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::TurboStreamFrom

      #: (move: untyped, box: untyped, media: untyped, ?items_by_media: untyped) -> void
      def initialize(move:, box:, media:, items_by_media: {})
        @move = move
        @box = box
        @media = media
        @items_by_media = items_by_media
      end

      #: () -> void
      def view_template
        header
        demo_banner
        div(class: "grid grid-cols-1 gap-section-gap lg:grid-cols-3") do
          capture_area
          session_region
        end
      end

      private

      # #199 — when recognition runs on the `fake` provider (the post-cutover
      # default), detections are canned sample data, not real recognition. Warn
      # the user so a fabricated result is never mistaken for a real one. Reuses
      # the attention-state tokens the recognition status chip already uses.

      #: () -> untyped
      def demo_banner
        return unless @move.recognition_provider == "fake"

        div(
          class: "mt-section-gap flex items-start gap-3 rounded-card border border-secondary/30 " \
                 "bg-secondary/15 px-4 py-3 text-body-md text-secondary",
          role: "status"
        ) do
          render Components::Icons::Alert.new(css: "mt-0.5 h-5 w-5 shrink-0")
          span { I18n.t("captures.demo_banner") }
        end
      end

      #: () -> untyped
      def header
        div(class: "flex flex-wrap items-center justify-between gap-4") do
          div(class: "flex items-center gap-3") do
            a(href: move_box_path(@move, @box),
              class: "rounded-full p-2 text-muted transition hover:bg-surface-container-high hover:text-text-warm") do
              render Components::Icons::ChevronRight.new(css: "h-5 w-5 rotate-180")
            end
            h2(class: "text-headline-lg-mobile md:text-headline-lg text-text-warm") { title }
          end
          span(class: "inline-flex items-center gap-2 rounded-full bg-surface-container-high px-4 py-2 " \
                      "text-label-caps uppercase text-muted") do
            span(class: "h-2 w-2 rounded-full bg-accent-sage")
            plain I18n.t("captures.online")
          end
        end
      end

      # Server-side multipart upload. The whole dashed tile is a single tap target
      # (a label wrapping a visually-hidden file input): tapping it opens the
      # camera (accept+capture) on mobile or the file picker on desktop. Selecting
      # a photo fires `change`, which the form-level auto-submit controller turns
      # into a submit — recognition starts immediately, with no shutter button.

      #: () -> untyped
      def capture_area
        render Components::Ui::Card.new(padding: "p-6", class: "lg:col-span-2") do
          form_with(url: move_box_capture_path(@move, @box), method: :post,
                    data: { controller: "auto-submit", action: "change->auto-submit#submit" }) do |form|
            label(
              class: "flex h-56 w-full cursor-pointer flex-col items-center justify-center gap-3 " \
                     "rounded-card border border-dashed border-card-border bg-surface-container-high " \
                     "text-muted transition hover:border-accent-sage hover:text-text-warm"
            ) do
              span(class: "flex h-16 w-16 items-center justify-center rounded-full " \
                          "bg-accent-sage/15 text-accent-sage") do
                render Components::Icons::Camera.new(css: "h-8 w-8")
              end
              span(class: "text-headline-md text-text-warm") { I18n.t("captures.tap_to_capture") }
              span(class: "text-body-md text-muted") { I18n.t("captures.capture_hint") }
              form.file_field :file, accept: "image/*", capture: "environment",
                                     required: true, class: "sr-only"
            end
          end
        end
      end

      #: () -> untyped
      def session_region
        aside(class: "flex flex-col gap-4") do
          div(class: "flex items-center justify-between px-1") do
            h3(class: "text-headline-md text-text-warm") { I18n.t("captures.session.title") }
            span(class: "text-label-caps uppercase text-muted") do
              I18n.t("captures.session.count", count: @media.size)
            end
          end
          # Live recognition state arrives over ActionCable as each run advances —
          # no polling (#241). The signed stream binds to this tenant-unique Box;
          # the subscriber replaces the panel by its stable id.
          turbo_stream_from(@box, :recognition)
          render Views::Captures::SessionPanel.new(
            box: @box, media: @media, items_by_media: @items_by_media
          )
          render Components::Ui::Button.new(
            label: I18n.t("captures.finish"), variant: :secondary, full_width: true,
            href: move_box_path(@move, @box)
          )
          render Components::Ui::Button.new(
            label: I18n.t("captures.add_item"), variant: :ghost, full_width: true, disabled: true
          )
        end
      end

      #: () -> untyped
      def title
        I18n.t("captures.title", number: Kernel.format("%03d", @box.number.to_i), room: room_label)
      end

      #: () -> String
      def room_label
        @box.room&.name.presence || I18n.t("boxes.card.no_room")
      end
    end
  end
end
