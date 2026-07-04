# frozen_string_literal: true

module Components
  module Icons
    class Search < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.circle(cx: "11", cy: "11", r: "7")
          s.path(d: "m20 20-3.6-3.6")
        end
      end
    end
  end
end
