# frozen_string_literal: true

module Components
  module Icons
    class Clock < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.circle(cx: "12", cy: "12", r: "8")
          s.path(d: "M12 8v4.2l2.6 2.6")
        end
      end
    end
  end
end
