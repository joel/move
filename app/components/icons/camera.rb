# frozen_string_literal: true

module Components
  module Icons
    class Camera < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M5 8a2 2 0 0 1 2-2h1.4l.8-1.6A1 1 0 0 1 10.1 4h3.8a1 1 0 0 1 .9.4L15.6 6H17a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2Z")
          s.circle(cx: "12", cy: "12.5", r: "3.2")
        end
      end
    end
  end
end
