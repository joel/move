# frozen_string_literal: true

module Components
  module Icons
    class Chart < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M4 20h16")
          s.path(d: "M6 20v-5")
          s.path(d: "M12 20V7")
          s.path(d: "M18 20v-9")
        end
      end
    end
  end
end
