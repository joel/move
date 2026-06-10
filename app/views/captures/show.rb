# frozen_string_literal: true

module Views
  module Captures
    # B2 — Capture image. Target box is always unambiguous in the header. Upload
    # is online-only (server-side via Active Storage); the session panel polls for
    # live recognition state. Renders in the AppShellLayout.
    class Show < Views::Base
      include Phlex::Rails::Helpers::FormWith

      def initialize(move:, box:, media:)
        @move = move
        @box = box
        @media = media
      end

      def view_template
        header
        div(class: "grid grid-cols-1 gap-section-gap lg:grid-cols-3") do
          capture_area
          session_region
        end
      end

      private

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

      # Server-side multipart upload. On mobile, accept+capture opens the camera.
      def capture_area
        render Components::Ui::Card.new(padding: "p-6", class: "lg:col-span-2") do
          form_with(url: move_box_capture_path(@move, @box), method: :post,
                    class: "flex flex-col items-center gap-6") do |form|
            div(class: "flex h-56 w-full items-center justify-center rounded-card " \
                       "border border-dashed border-card-border bg-surface-container-high text-muted") do
              render Components::Icons::Camera.new(css: "h-12 w-12")
            end
            form.file_field :file, accept: "image/jpeg,image/png,image/webp",
                                   capture: "environment", required: true,
                                   class: "w-full text-body-md text-muted file:mr-4 file:rounded-full " \
                                          "file:border-0 file:bg-surface-container-high file:px-4 file:py-2 " \
                                          "file:text-text-warm"
            form.submit I18n.t("captures.shutter"), class: "ha-button ha-button-primary w-full"
          end
        end
      end

      def session_region
        aside(class: "flex flex-col gap-4") do
          div(class: "flex items-center justify-between px-1") do
            h3(class: "text-headline-md text-text-warm") { I18n.t("captures.session.title") }
            span(class: "text-label-caps uppercase text-muted") do
              I18n.t("captures.session.count", count: @media.size)
            end
          end
          div(
            data: {
              controller: "recognition-poller",
              recognition_poller_url_value: move_box_capture_session_path(@move, @box),
              recognition_poller_interval_value: 2500
            }
          ) do
            div(data: { recognition_poller_target: "frame" }) do
              render Views::Captures::SessionPanel.new(box: @box, media: @media)
            end
          end
          render Components::Ui::Button.new(
            label: I18n.t("captures.finish"), variant: :secondary, full_width: true,
            href: move_box_path(@move, @box)
          )
          render Components::Ui::Button.new(
            label: I18n.t("captures.add_item"), variant: :ghost, full_width: true, disabled: true
          )
        end
      end

      def title
        I18n.t("captures.title", number: Kernel.format("%03d", @box.number.to_i), room: room_label)
      end

      def room_label
        @box.room&.name.presence || I18n.t("boxes.card.no_room")
      end
    end
  end
end
