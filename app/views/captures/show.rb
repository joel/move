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

      # The capture surface (#616): an in-app getUserMedia viewfinder is the
      # primary camera — it renders inside the app window, so the PWA manifest's
      # portrait lock applies to capture (the native camera app it replaces
      # rotates freely and cannot be locked). The dashed tile remains the
      # baseline markup and the no-camera affordance: primary on fine pointers
      # (desktop) and the fallback when the camera is denied or dies. Without
      # `capture` the input opens the OS chooser (camera app or gallery).
      # The wrapper hears the input's `change` (an upload started — lock the
      # shutter; the pipeline's file input is single-slot) and the form's
      # turbo:submit-end (settled — re-arm).

      #: () -> untyped
      def capture_area
        render Components::Ui::Card.new(padding: "p-6", class: "lg:col-span-2") do
          div(class: "flex flex-col gap-4",
              data: { controller: "camera-capture",
                      action: "change->camera-capture#uploadStarted " \
                              "turbo:submit-start->camera-capture#uploadInFlight " \
                              "turbo:submit-end->camera-capture#uploadSettled" }) do
            viewfinder
            capture_form
            camera_controls
          end
        end
      end

      # Live viewfinder — hidden until the camera-capture controller streams.
      # The shutter overlays the video bottom-center (native-camera convention);
      # the flash layer pulses as capture feedback.

      #: () -> untyped
      def viewfinder
        div(class: "relative mx-auto hidden aspect-3/4 w-full max-w-md overflow-hidden " \
                   "rounded-card bg-black",
            data: { "camera-capture-target": "viewfinder" }) do
          video(class: "h-full w-full object-cover", playsinline: true, muted: true, autoplay: true,
                data: { "camera-capture-target": "video" })
          div(class: "absolute inset-0 flex flex-col items-center justify-center gap-3 " \
                     "bg-surface-container-high text-muted",
              data: { "camera-capture-target": "status" }) do
            render Components::Icons::Camera.new(css: "h-8 w-8 animate-pulse")
            span(class: "px-6 text-center text-body-md") { I18n.t("captures.viewfinder.allow") }
          end
          div(class: "pointer-events-none absolute inset-0 bg-white opacity-0 " \
                     "transition-opacity duration-150",
              data: { "camera-capture-target": "flash" })
          button(type: "button", disabled: true,
                 class: "absolute bottom-4 left-1/2 h-16 w-16 -translate-x-1/2 rounded-full " \
                        "border-4 border-accent-sage bg-text-warm shadow-lg transition " \
                        "active:scale-90 disabled:opacity-50 focus-visible:outline-2 " \
                        "focus-visible:outline-offset-2 focus-visible:outline-accent-sage",
                 aria: { label: I18n.t("captures.viewfinder.shutter") },
                 data: { "camera-capture-target": "shutter", action: "camera-capture#capture" })
        end
      end

      #: () -> untyped
      def capture_form
        # capture-upload (#547): downscales the photo to <=2048px JPEG in the
        # browser before submitting, so a small file goes over the wire (the
        # server still normalizes it as the authority). Falls back to the
        # original on any error, so capture never breaks. When direct upload is
        # enabled (#572), it also PUTs the photo straight to R2 and submits a
        # signed_id instead of the bytes — falling back to this same POST if the
        # direct upload fails. Viewfinder frames enter the same pipeline: the
        # camera-capture controller inserts the file here and dispatches `change`.
        form_with(url: move_box_capture_path(@move, @box), method: :post,
                  data: capture_form_data) do |form|
          label(
            class: "flex h-56 w-full cursor-pointer flex-col items-center justify-center gap-3 " \
                   "rounded-card border border-dashed border-card-border bg-surface-container-high " \
                   "text-muted transition hover:border-accent-sage hover:text-text-warm",
            data: { "camera-capture-target": "fallback" }
          ) do
            span(class: "flex h-16 w-16 items-center justify-center rounded-full " \
                        "bg-accent-sage/15 text-accent-sage") do
              render Components::Icons::Camera.new(css: "h-8 w-8")
            end
            span(class: "text-headline-md text-text-warm") { I18n.t("captures.tap_to_capture") }
            span(class: "text-body-md text-muted") { I18n.t("captures.capture_hint") }
            # click->guardPick: a file input's click is cancelable before the
            # dialog opens — the choke point that blocks any pick while an
            # upload is pending (the input is single-slot).
            form.file_field :file, accept: "image/*",
                                   required: true, class: "sr-only",
                                   data: { "capture-upload-target": "file",
                                           "camera-capture-target": "input",
                                           action: "click->camera-capture#guardPick" }
          end
          # Carries the R2 signed_id when the browser direct-uploads (#572); empty
          # on the server-proxied path. StartIngest prefers it over :file.
          form.hidden_field :signed_id, data: { "capture-upload-target": "signedId" }
        end
      end

      # Quiet controls under the capture surface: "Use camera" (fine pointers,
      # starts the viewfinder on demand — and the retry affordance after a
      # camera failure), "Choose from library" (while streaming), and the
      # camera-unavailable note. All hidden by default; the camera-capture
      # controller's state table reveals whichever the state calls for.

      #: () -> untyped
      def camera_controls
        div(class: "flex flex-col items-center gap-2") do
          button(type: "button",
                 class: "hidden text-body-md text-accent-sage underline-offset-4 transition " \
                        "hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 " \
                        "focus-visible:outline-accent-sage",
                 data: { "camera-capture-target": "start", action: "camera-capture#start" }) do
            plain I18n.t("captures.viewfinder.use_camera")
          end
          button(type: "button",
                 class: "hidden text-body-md text-muted underline-offset-4 transition " \
                        "hover:text-text-warm hover:underline focus-visible:outline-2 " \
                        "focus-visible:outline-offset-2 focus-visible:outline-accent-sage",
                 data: { "camera-capture-target": "library", action: "camera-capture#openLibrary" }) do
            plain I18n.t("captures.viewfinder.library")
          end
          p(class: "hidden text-center text-body-md text-muted",
            data: { "camera-capture-target": "note" }) do
            plain I18n.t("captures.viewfinder.unavailable")
          end
        end
      end

      # Only advertise the presign endpoint when direct upload is enabled (prod) —
      # otherwise the controller stays on the server-proxied POST with no wasted
      # presign round-trip.

      #: () -> Hash[Symbol, untyped]
      def capture_form_data
        # camera-capture:recover — a failsafe expiry (#622): reset the pipeline
        # exactly as turbo:submit-end would, so recovered controls aren't left
        # with a disabled input / stale signed_id from the hung submission.
        data = { controller: "capture-upload",
                 action: "change->capture-upload#submit turbo:submit-end->capture-upload#reset " \
                         "camera-capture:recover->capture-upload#reset" }
        if Rails.application.config.x.direct_upload_enabled
          data[:"capture-upload-direct-upload-url-value"] =
            view_context.move_box_capture_direct_upload_path(@move, @box)
        end
        data
      end

      #: () -> untyped
      def session_region
        aside(class: "flex flex-col gap-4") do
          # Title + count now live inside SessionPanel (the replaced target) so a
          # capture/broadcast update refreshes the count (#546). Live recognition
          # state arrives over ActionCable as each run advances — no polling
          # (#241). The signed stream binds to this tenant-unique Box; the
          # subscriber replaces the panel by its stable id.
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
