# frozen_string_literal: true

module Components
  module Icons
    # Two stacked squares — the duplicate/copy affordance (box card, #658).
    class Duplicate < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.rect(x: "9", y: "9", width: "13", height: "13", rx: "2")
          s.path(d: "M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1")
        end
      end
    end
  end
end
