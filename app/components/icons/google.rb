# frozen_string_literal: true

module Components
  module Icons
    class Google < Phlex::SVG
      def initialize(css: "h-5 w-5", **attrs)
        @css = css
        @attrs = attrs
      end

      def view_template
        svg(class: @css, **@attrs, viewBox: "0 0 24 24",
            aria_hidden: "true") do |s|
          s.path(
            d: "M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 " \
               "5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z",
            fill: "#4285F4"
          )
          s.path(
            d: "M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 " \
               "1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84A10.997 " \
               "10.997 0 0 0 12 23z",
            fill: "#34A853"
          )
          s.path(
            d: "M5.84 14.09A6.611 6.611 0 0 1 5.5 12c0-.72.12-1.42.34-2.09V7.07H2.18A10.96 " \
               "10.96 0 0 0 1 12c0 1.77.42 3.45 1.18 4.93l2.66-2.84z",
            fill: "#FBBC05"
          )
          s.path(
            d: "M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15A10.94 10.94 " \
               "0 0 0 12 1 10.997 10.997 0 0 0 2.18 7.07l3.66 2.84c.87-2.6 " \
               "3.3-4.53 6.16-4.53z",
            fill: "#EA4335"
          )
        end
      end
    end
  end
end
