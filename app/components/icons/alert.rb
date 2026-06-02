# frozen_string_literal: true

module Components
  module Icons
    class Alert < Components::Icons::Base
      def view_template
        svg(class: @css, **@attrs, viewBox: "0 0 20 20", fill: "none", aria_hidden: "true") do |s|
          s.path(
            d: "M10 6v5M10 14.2v.2",
            stroke: "currentColor",
            stroke_width: "1.7",
            stroke_linecap: "round"
          )
          s.circle(
            cx: "10",
            cy: "10",
            r: "6.8",
            stroke: "currentColor",
            stroke_width: "1.5"
          )
        end
      end
    end
  end
end
