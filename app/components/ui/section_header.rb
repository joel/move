# frozen_string_literal: true

module Components
  module Ui
    # Section heading: an optional `label-caps` eyebrow, a headline title, an
    # optional subtitle, and a trailing actions slot (block).
    #
    #   render Components::Ui::SectionHeader.new(eyebrow: "Move", title: "My Boxes")
    class SectionHeader < Components::Base
      #: (title: untyped, ?eyebrow: untyped, ?subtitle: untyped, **untyped) -> void
      def initialize(title:, eyebrow: nil, subtitle: nil, **attrs)
        @title = title
        @eyebrow = eyebrow
        @subtitle = subtitle
        @attrs = attrs
      end

      #: () ?{ (*untyped) -> untyped } -> untyped
      def view_template(&block)
        div(
          class: "flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between",
          **@attrs
        ) do
          div(class: "flex flex-col gap-1") do
            p(class: "text-label-caps uppercase text-muted") { @eyebrow } if @eyebrow
            h2(class: "text-headline-lg-mobile md:text-headline-xl text-text-warm") do
              @title
            end
            p(class: "text-body-lg text-on-surface-variant") { @subtitle } if @subtitle
          end
          div(class: "flex flex-wrap gap-3", &block) if block
        end
      end
    end
  end
end
