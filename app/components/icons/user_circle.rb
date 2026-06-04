# frozen_string_literal: true

module Components
  module Icons
    class UserCircle < Components::Icons::Base
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.circle(cx: "12", cy: "12", r: "9")
          s.circle(cx: "12", cy: "10", r: "3")
          s.path(d: "M6.6 18.8a6 6 0 0 1 10.8 0")
        end
      end
    end
  end
end
