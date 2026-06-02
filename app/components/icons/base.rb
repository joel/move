# frozen_string_literal: true

module Components
  module Icons
    class Base < Phlex::SVG
      def initialize(css: "h-4 w-4", **attrs)
        @css = css
        @attrs = attrs
      end
    end
  end
end
