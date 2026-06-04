# frozen_string_literal: true

module Components
  module Icons
    class Retry < Components::Icons::Base
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M20 12a8 8 0 1 1-2.3-5.6")
          s.path(d: "M20 4v4h-4")
        end
      end
    end
  end
end
