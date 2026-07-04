# frozen_string_literal: true

module Components
  module Icons
    class Sparkles < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M12 4.5 13.7 9 18 10.5 13.7 12 12 16.5 10.3 12 6 10.5 10.3 9 12 4.5Z")
          s.path(d: "M18 14.5 18.8 16.7 21 17.5 18.8 18.3 18 20.5 17.2 18.3 15 17.5 17.2 16.7 18 14.5Z")
        end
      end
    end
  end
end
