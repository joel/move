# frozen_string_literal: true

module Components
  module Ui
    # In-app camera viewfinder surface (#618): a portrait 3:4 `rounded-card`
    # black frame holding a muted, inline, autoplaying `object-cover` <video>,
    # plus an overlay slot (the block) for whatever the surface layers on top —
    # status, aim reticle, flash, shutter. The stream itself is driven by the
    # shared `camera/stream` JS module from the Stimulus controller named in
    # `controller:`, whose `video` target the <video> becomes.
    #
    # The component owns the surface look; the caller owns layout (`css:` —
    # width cap, centring, `hidden` until streaming) and its own wrapper `data:`
    # (e.g. the controller's `viewfinder` target):
    #
    #   render Components::Ui::CameraViewfinder.new(
    #     controller: "camera-capture", css: "mx-auto hidden max-w-md",
    #     data: { camera_capture_target: "viewfinder" }
    #   ) do
    #     button(type: "button", class: Components::Ui::CameraViewfinder::SHUTTER_CLASSES, ...)
    #   end
    #
    # Overlay children are absolutely positioned by the caller (`absolute
    # inset-0 …`); the frame is `relative overflow-hidden`, so they clip to the
    # rounded corners. Used by B2 capture, C2 review Retake (#619) and E2 scan.
    class CameraViewfinder < Components::Base
      # The bespoke round shutter overlaid bottom-centre (native-camera
      # convention): a 64px warm-off-white disc in a 4px sage ring, press =
      # shrink, with the kit's disabled + focus-visible states.
      SHUTTER_CLASSES = "absolute bottom-4 left-1/2 h-16 w-16 -translate-x-1/2 rounded-full " \
                        "border-4 border-accent-sage bg-text-warm shadow-lg transition " \
                        "active:scale-90 disabled:opacity-50 focus-visible:outline-2 " \
                        "focus-visible:outline-offset-2 focus-visible:outline-accent-sage"

      # The Turbo-cache lifecycle every consumer's controller wires on its
      # root (#987): `teardown` releases the camera before Turbo snapshots the
      # page; `resume` restarts it when the page outlives the cache (Turbo can
      # cache without replacing the body — a non-Turbo history entry, a
      # morphing refresh). popstate is in the list because Turbo's empty-state
      # history pop fires neither turbo:load nor turbo:render.
      CACHE_EVENTS = {
        "turbo:before-cache@document" => "teardown",
        "turbo:load@document" => "resume",
        "turbo:render@document" => "resume",
        "popstate@window" => "resume"
      }.freeze

      # The `data-action` descriptors for CACHE_EVENTS on `controller`.
      #: (String controller) -> String
      def self.cache_actions(controller)
        CACHE_EVENTS.map { |event, method| "#{event}->#{controller}##{method}" }.join(" ")
      end

      #: (controller: String, ?css: String?, ?data: Hash[untyped, untyped]) -> void
      def initialize(controller:, css: nil, data: {})
        @controller = controller
        @css = css
        @data = data
      end

      #: () ?{ (*untyped) -> untyped } -> untyped
      def view_template(&)
        div(class: frame_classes, data: @data) do
          video(class: "h-full w-full object-cover", playsinline: true, muted: true, autoplay: true,
                data: { "#{@controller}-target": "video" })
          yield if block_given?
        end
      end

      private

      #: () -> String
      def frame_classes
        ["relative aspect-3/4 w-full overflow-hidden rounded-card bg-black", @css].compact.join(" ")
      end
    end
  end
end
