# frozen_string_literal: true

module Components
  module Icons
    # A "photo unavailable" glyph (image frame with a slash) — shown where a
    # media's master blob is unrecoverable (#563), to distinguish a lost photo
    # from a not-yet-captured one (Camera).
    class ImageOff < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M21 15.3V6a2 2 0 0 0-2-2H8.7")
          s.path(d: "M4.3 4.3A2 2 0 0 0 3 6v12a2 2 0 0 0 2 2h12a2 2 0 0 0 1.7-1")
          s.path(d: "m8 11-3 4h9")
          s.path(d: "M3 3 21 21")
        end
      end
    end
  end
end
