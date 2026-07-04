# frozen_string_literal: true

module Components
  module Icons
    class Tag < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M3 7v4.6c0 .5.2 1 .6 1.4l7.4 7.4a2 2 0 0 0 2.8 0l4.6-4.6a2 2 0 0 0 0-2.8" \
                    "L11 5.6a2 2 0 0 0-1.4-.6H5a2 2 0 0 0-2 2Z")
          s.circle(cx: "7.5", cy: "7.5", r: "1.1", fill: "currentColor", stroke: "none")
        end
      end
    end
  end
end
