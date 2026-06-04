# frozen_string_literal: true

module Components
  module Icons
    class Bolt < Components::Icons::Base
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M13 3 5 13.5h6L11 21l8-10.5h-6L13 3Z")
        end
      end
    end
  end
end
