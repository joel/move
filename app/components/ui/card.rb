# frozen_string_literal: true

module Components
  module Ui
    # 20px-radius card with tonal lift and a 1px hairline edge (no drop shadow).
    # Optional `micro_bar:` slot renders a bottom summary strip (Boxes Home).
    #
    #   render Components::Ui::Card.new { "Body" }
    #   render Components::Ui::Card.new(micro_bar: ->(c) { c.plain "12/12 packed" })
    class Card < Components::Base
      #: (?interactive: untyped, ?padding: untyped, ?micro_bar: untyped, **untyped) -> void
      def initialize(interactive: false, padding: "p-5", micro_bar: nil, **attrs)
        @interactive = interactive
        @padding = padding
        @micro_bar = micro_bar
        @attrs = attrs
      end

      #: () ?{ (*untyped) -> untyped } -> untyped
      def view_template(&)
        div(class: classes, **@attrs) do
          div(class: "flex flex-1 flex-col gap-4", &)
          render_micro_bar if @micro_bar
        end
      end

      private

      #: () -> untyped
      def render_micro_bar
        div(class: "mt-auto flex flex-col gap-2 border-t border-card-border pt-4") do
          @micro_bar.call(self)
        end
      end

      #: () -> String
      def classes
        [
          "flex flex-col rounded-card bg-card border border-card-border",
          @padding,
          (if @interactive
             "transition hover:-translate-y-0.5 hover:bg-surface-container-high " \
               "cursor-pointer"
           end)
        ].compact.join(" ")
      end
    end
  end
end
