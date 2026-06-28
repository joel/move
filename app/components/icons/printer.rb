# frozen_string_literal: true

module Components
  module Icons
    # Printer — the "Print label" / "Print manifest" actions (B1 Manage-box sheet).
    class Printer < Components::Icons::Base
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M7 9V4h10v5")
          s.path(d: "M7 18H5a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-2")
          s.rect(x: "7", y: "15", width: "10", height: "6", rx: "1")
        end
      end
    end
  end
end
