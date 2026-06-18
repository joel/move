# frozen_string_literal: true

module Views
  module Scans
    # E2 — the live QR scanner. A rear-camera viewfinder (decoded client-side by
    # controllers/qr_scanner_controller.js via jsQR) over a manual-entry fallback
    # for when the camera is unavailable. On a hit the controller navigates to the
    # Move-scoped resolve route. Renders in the Move app shell.
    class Show < Views::Base
      def initialize(move:)
        @move = move
      end

      def view_template
        div(
          class: "flex flex-col items-center gap-6",
          data: { controller: "qr-scanner", qr_scanner_resolve_url_value: move_scan_path(@move) }
        ) do
          viewfinder
          p(class: "max-w-sm text-center text-sm text-muted") { I18n.t("scans.show.hint") }
          manual_entry
          fallback
        end
      end

      private

      def viewfinder
        div(class: "relative aspect-[3/4] w-full max-w-sm overflow-hidden rounded-card " \
                   "border border-card-border bg-black") do
          video(
            data: { qr_scanner_target: "video" }, muted: true, autoplay: true, playsinline: true,
            class: "h-full w-full object-cover"
          )
          canvas(data: { qr_scanner_target: "canvas" }, class: "hidden")
          overlay
        end
      end

      def overlay
        div(class: "pointer-events-none absolute inset-0 flex flex-col items-center " \
                   "justify-center gap-6") do
          span(class: "rounded-full bg-black/60 px-4 py-2 text-sm text-white") do
            I18n.t("scans.show.aim")
          end
          div(class: "h-48 w-48 rounded-2xl border-2 border-accent-sage/80")
        end
      end

      # Camera-independent fallback: type the box code printed on the label.
      def manual_entry
        form(
          data: { action: "qr-scanner#submitManual" },
          class: "flex w-full max-w-sm items-center gap-2"
        ) do
          input(
            type: "text", name: "token", autocomplete: "off",
            placeholder: I18n.t("scans.show.manual_placeholder"),
            data: { qr_scanner_target: "manual" },
            class: "min-w-0 flex-1 rounded-full border border-card-border bg-card px-4 py-3 " \
                   "text-body-md text-text-warm placeholder:text-muted focus:outline-none " \
                   "focus:ring-2 focus:ring-accent-sage"
          )
          render Components::Ui::Button.new(
            label: I18n.t("scans.show.manual_submit"), type: "submit", variant: :secondary
          )
        end
      end

      def fallback
        div(
          data: { qr_scanner_target: "fallback" },
          class: "hidden max-w-sm text-center text-sm text-muted"
        ) { p { I18n.t("scans.show.camera_unavailable") } }
      end
    end
  end
end
