# frozen_string_literal: true

module Components
  module Icons
    class ChevronRight < Components::Icons::Base
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "m9 6 6 6-6 6")
        end
      end
    end
  end
end
