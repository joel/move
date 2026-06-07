# frozen_string_literal: true

module Components
  module Icons
    # A four-square grid — the medallion for the Categories vocabulary.
    class Category < Components::Icons::Base
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "none",
          stroke: "currentColor", stroke_width: "1.6",
          stroke_linecap: "round", stroke_linejoin: "round", aria_hidden: "true"
        ) do |s|
          s.rect(x: "3.5", y: "3.5", width: "7", height: "7", rx: "1.8")
          s.rect(x: "13.5", y: "3.5", width: "7", height: "7", rx: "1.8")
          s.rect(x: "3.5", y: "13.5", width: "7", height: "7", rx: "1.8")
          s.rect(x: "13.5", y: "13.5", width: "7", height: "7", rx: "1.8")
        end
      end
    end
  end
end
