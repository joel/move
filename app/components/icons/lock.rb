# frozen_string_literal: true

module Components
  module Icons
    # Closed padlock — the "Seal box" lifecycle action (B1 Manage-box sheet).
    class Lock < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.rect(x: "5", y: "11", width: "14", height: "10", rx: "2")
          s.path(d: "M8 11V7a4 4 0 0 1 8 0v4")
        end
      end
    end
  end
end
