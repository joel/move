# frozen_string_literal: true

module Components
  module Icons
    class Pencil < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M16.4 4.6a2.1 2.1 0 0 1 3 3L8 19l-4 1 1-4 11.4-11.4Z")
          s.path(d: "m14 7 3 3")
        end
      end
    end
  end
end
