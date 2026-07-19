# frozen_string_literal: true

module Components
  module Icons
    # Shield with a check — the Insurance exports hub (#702).
    class Shield < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.path(d: "M12 3l7 3v5c0 4.5-3 8.2-7 10-4-1.8-7-5.5-7-10V6l7-3z")
          s.path(d: "M9.5 12l1.8 1.8L15 10")
        end
      end
    end
  end
end
