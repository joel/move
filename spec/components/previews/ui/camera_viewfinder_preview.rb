# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::CameraViewfinder (#618). Previews
  # render the static surface only — no Stimulus controller is attached, so
  # the camera never starts here and the black frame shows what a surface
  # looks like before its stream arrives. Overlays are the two shipped
  # recipes (B2 capture shutter, E2 scan reticle).
  class CameraViewfinderPreview < Lookbook::Preview
    # B2 capture — the shutter overlaid bottom-centre (disabled until live).
    def capture
      render Components::Ui::CameraViewfinder.new(controller: "preview", css: "mx-auto max-w-md") do |c|
        c.button(type: "button", aria_label: "Take photo",
                 class: Components::Ui::CameraViewfinder::SHUTTER_CLASSES)
      end
    end

    # B2 capture while the permission prompt is open — the status overlay.
    def requesting
      render Components::Ui::CameraViewfinder.new(controller: "preview", css: "mx-auto max-w-md") do |c|
        c.div(class: "absolute inset-0 flex flex-col items-center justify-center gap-3 " \
                     "bg-surface-container-high text-muted") do
          c.render Components::Icons::Camera.new(css: "h-8 w-8 animate-pulse")
          c.span(class: "px-6 text-center text-body-md") { "Allow camera access to start capturing" }
        end
        c.button(type: "button", disabled: true, aria_label: "Take photo",
                 class: Components::Ui::CameraViewfinder::SHUTTER_CLASSES)
      end
    end

    # E2 scan — the aim hint and reticle.
    def scan
      render Components::Ui::CameraViewfinder.new(controller: "preview", css: "mx-auto max-w-sm") do |c|
        c.div(class: "pointer-events-none absolute inset-0 flex flex-col items-center " \
                     "justify-center gap-6") do
          c.span(class: "rounded-full bg-black/60 px-4 py-2 text-sm text-white") { "Point at a box label" }
          c.div(class: "h-48 w-48 rounded-2xl border-2 border-accent-sage/80")
        end
      end
    end
  end
end
