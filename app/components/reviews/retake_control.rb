# frozen_string_literal: true

module Components
  module Reviews
    # C2's "Retake this photo" section (#619): replace the photo's image in
    # place (Captures::Retake) — recover a corrupt master or swap a bad shot.
    #
    # "Take a new photo" opens the in-app viewfinder (Ui::CameraViewfinder +
    # the camera-capture controller, the B2 capture camera), so the shot is
    # taken inside the app window under the PWA's portrait lock — the native
    # camera app the old `capture` input handed off to rotates to landscape and
    # cannot be locked by a web app. The shutter's frame enters the same
    # capture-upload pipeline (downscale + submit) as a chooser pick, so the
    # controller's upload lock (single-slot input) and per-start generation
    # token apply exactly as on B2. Here the camera never auto-starts (capture
    # is a secondary action on this screen) and "Cancel" releases it; denial or
    # no camera leaves the chooser as the fallback.
    #
    # The auto-submit action is on the FILE input, not the form, so toggling the
    # re-scan checkbox never submits an empty upload.
    class RetakeControl < Components::Base
      include Phlex::Rails::Helpers::FormWith

      # The quiet text actions under the viewfinder (B2's camera-controls recipe).
      QUIET_LINK = "text-body-md text-muted underline-offset-4 transition hover:text-text-warm " \
                   "hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 " \
                   "focus-visible:outline-accent-sage"

      # url: the retake POST (queue param already threaded by the caller).
      # rescan: offer "Also re-scan for items" (the box can still capture).

      #: (url: String, rescan: bool) -> void
      def initialize(url:, rescan:)
        @url = url
        @rescan = rescan
      end

      #: () -> void
      def view_template
        div(class: "mt-stack-gap flex flex-col gap-3 border-t border-card-border pt-stack-gap",
            data: { controller: "camera-capture", "camera-capture-autostart-value": "false",
                    action: "turbo:submit-start->camera-capture#uploadInFlight " \
                            "turbo:submit-end->camera-capture#uploadSettled " +
                            Components::Ui::CameraViewfinder.cache_actions("camera-capture") }) do
          span(class: "text-label-caps uppercase text-muted") { I18n.t("reviews.photo.retake_heading") }
          viewfinder
          retake_form
          camera_controls
        end
      end

      private

      # Hidden until the camera streams — B2's overlay recipe (permission
      # status, capture flash, shutter).

      #: () -> untyped
      def viewfinder
        render Components::Ui::CameraViewfinder.new(
          controller: "camera-capture", css: "mx-auto hidden max-w-sm",
          data: { "camera-capture-target": "viewfinder" }
        ) do
          div(class: "absolute inset-0 flex flex-col items-center justify-center gap-3 " \
                     "bg-surface-container-high text-muted",
              data: { "camera-capture-target": "status" }) do
            render Components::Icons::Camera.new(css: "h-8 w-8 animate-pulse")
            span(class: "px-6 text-center text-body-md") { I18n.t("reviews.photo.retake_allow") }
          end
          div(class: "pointer-events-none absolute inset-0 bg-white opacity-0 transition-opacity duration-150",
              data: { "camera-capture-target": "flash" })
          button(type: "button", disabled: true,
                 class: Components::Ui::CameraViewfinder::SHUTTER_CLASSES,
                 aria: { label: I18n.t("captures.viewfinder.shutter") },
                 data: { "camera-capture-target": "shutter", action: "camera-capture#capture" })
        end
      end

      # Reset rides camera-capture:settle (the controller's demuxed terminal
      # event, #622), never raw turbo:submit-end.

      #: () -> untyped
      def retake_form
        form_with(url: @url, method: :post,
                  data: { controller: "capture-upload", action: "camera-capture:settle->capture-upload#reset" },
                  class: "flex flex-col gap-3") do |form|
          rescan_checkbox if @rescan
          # The wrapper is the state table's `hidden` toggle, so the pill keeps
          # its own display utility.
          div(class: "hidden", data: { "camera-capture-target": "start" }) do
            render Components::Ui::Button.new(
              label: I18n.t("reviews.photo.retake_camera"), icon: Components::Icons::Camera, full_width: true,
              data: { action: "camera-capture#start" }
            )
          end
          chooser(form)
        end
      end

      #: () -> untyped
      def rescan_checkbox
        label(class: "flex items-center gap-2 text-body-md text-muted") do
          input(type: "checkbox", name: "rerun_recognition", value: "1",
                class: "h-4 w-4 rounded border-card-border text-accent-sage focus:ring-accent-sage")
          plain I18n.t("reviews.photo.retake_rescan")
        end
      end

      # The camera-capture fallback: a label around the hidden file input.
      # Without `capture` it opens the OS chooser. click->guardPick blocks a
      # pick while an upload is pending (the input is single-slot); the
      # uploadStarted action precedes submit so the lock is raised first.

      #: (untyped form) -> untyped
      def chooser(form)
        div(data: { "camera-capture-target": "fallback" }) do
          label(class: "#{Components::Ui::Button.classes(variant: :secondary, full_width: true)} cursor-pointer") do
            span { I18n.t("reviews.photo.retake_choose") }
            form.file_field :file, accept: "image/*", required: true, class: "sr-only",
                                   data: { "capture-upload-target": "file", "camera-capture-target": "input",
                                           action: "click->camera-capture#guardPick " \
                                                   "change->camera-capture#uploadStarted " \
                                                   "change->capture-upload#submit" }
          end
        end
      end

      # Revealed by the camera-capture state table: "Choose from library" and
      # "Cancel" while the camera is live, the unavailable note after a failure.
      # While the upload lock is held Cancel hides and "Replacing photo…" shows
      # instead (#991) — the POST in flight still replaces the photo, so a
      # Cancel there would lie. The status takes focus (tabindex -1) when the
      # control a keyboard user was on hides under them.

      #: () -> untyped
      def camera_controls
        div(class: "flex flex-col items-center gap-2") do
          p(class: "hidden text-center text-body-md text-text-warm", role: "status", tabindex: "-1",
            data: { "camera-capture-target": "pending" }) do
            plain I18n.t("reviews.photo.retake_pending")
          end
          button(type: "button", class: "hidden #{QUIET_LINK}",
                 data: { "camera-capture-target": "library", action: "camera-capture#openLibrary" }) do
            plain I18n.t("captures.viewfinder.library")
          end
          button(type: "button", class: "hidden #{QUIET_LINK}",
                 data: { "camera-capture-target": "close", action: "camera-capture#close" }) do
            plain I18n.t("reviews.photo.retake_cancel")
          end
          p(class: "hidden text-center text-body-md text-muted", data: { "camera-capture-target": "note" }) do
            plain I18n.t("reviews.photo.retake_unavailable")
          end
        end
      end
    end
  end
end
