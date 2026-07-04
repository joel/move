# frozen_string_literal: true

module Components
  module Icons
    class Menu < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M4 7h16")
          s.path(d: "M4 12h16")
          s.path(d: "M4 17h16")
        end
      end
    end
  end
end
