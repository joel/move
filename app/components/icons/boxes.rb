# frozen_string_literal: true

module Components
  module Icons
    class Boxes < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M3 7.5 12 3l9 4.5v9L12 21l-9-4.5v-9Z")
          s.path(d: "M3 7.5 12 12l9-4.5")
          s.path(d: "M12 12v9")
        end
      end
    end
  end
end
