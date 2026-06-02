# frozen_string_literal: true

module Components
  module Icons
    class Moon < Components::Icons::Base
      def view_template
        svg(class: @css, **@attrs, viewBox: "0 0 20 20", fill: "none", aria_hidden: "true") do |s|
          s.path(
            d: "M14.8 12.8A6.2 6.2 0 0 1 7.2 5.2a6.8 6.8 0 1 0 7.6 7.6z",
            stroke: "currentColor",
            stroke_width: "1.4",
            stroke_linejoin: "round"
          )
        end
      end
    end
  end
end
