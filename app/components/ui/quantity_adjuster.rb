# frozen_string_literal: true

module Components
  module Ui
    # Horizontal pill with large +/- tap targets and a centred value. Behaviour
    # (incrementing) is wired in a later phase; D0 ships the visual primitive.
    #
    #   render Components::Ui::QuantityAdjuster.new(name: "qty", value: 1)
    class QuantityAdjuster < Components::Base
      def initialize(name:, value: 1, min: 0, **attrs)
        @name = name
        @value = value
        @min = min
        @attrs = attrs
      end

      def view_template
        div(
          class: "inline-flex items-center gap-1 rounded-full " \
                 "bg-surface-container-high p-1",
          **@attrs
        ) do
          step_button(:decrease, Components::Icons::Minus)
          span(class: "min-w-10 text-center text-body-lg font-bold tabular-nums") do
            @value.to_s
          end
          input(type: "hidden", name: @name, value: @value)
          step_button(:increase, Components::Icons::Plus)
        end
      end

      private

      def step_button(action, icon)
        button(
          type: "button",
          aria_label: I18n.t("ui.quantity.#{action}"),
          class: "flex h-10 w-10 items-center justify-center rounded-full " \
                 "bg-card text-text-warm transition active:scale-95 " \
                 "hover:bg-surface-container-highest"
        ) do
          render icon.new(css: "h-5 w-5")
        end
      end
    end
  end
end
