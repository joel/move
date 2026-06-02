# frozen_string_literal: true

module Components
  module Icons
    class Close < Components::Icons::Base
      def view_template
        svg(class: @css, **@attrs, viewBox: "0 0 20 20", fill: "none", aria_hidden: "true") do |s|
          s.path(
            d: "M6 6l8 8M14 6l-8 8",
            stroke: "currentColor",
            stroke_width: "1.6",
            stroke_linecap: "round"
          )
        end
      end
    end
  end
end
