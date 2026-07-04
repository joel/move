# frozen_string_literal: true

module Components
  module Ui
    # Pill chip in `label-caps` type with a low-saturation tint that encodes its
    # kind. `selected: true` fills it solid (used by filter rows).
    #
    #   render Components::Ui::Chip.new(label: "Kitchen", kind: :room)
    class Chip < Components::Base
      # sage = rooms, terracotta = tags, neutral = categories (brand usage law).
      KINDS = {
        room: "bg-accent-sage/15 text-accent-sage",
        tag: "bg-secondary/15 text-secondary",
        category: "bg-surface-container-high text-on-surface-variant"
      }.freeze

      #: (label: untyped, ?kind: untyped, ?selected: untyped, **untyped) -> void
      def initialize(label:, kind: :category, selected: false, **attrs)
        @label = label
        @kind = kind
        @selected = selected
        @attrs = attrs
      end

      #: () -> void
      def view_template
        span(class: classes, **@attrs) { @label }
      end

      private

      #: () -> String
      def classes
        tint = @selected ? "bg-accent-sage text-page" : KINDS.fetch(@kind, KINDS[:category])
        [
          "inline-flex items-center rounded-full px-3 py-1",
          "text-label-caps uppercase whitespace-nowrap",
          tint
        ].join(" ")
      end
    end
  end
end
