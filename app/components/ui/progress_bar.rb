# frozen_string_literal: true

module Components
  module Ui
    # Pill-shaped progress bar with a sage fill (boxes packed / items reviewed).
    #
    #   render Components::Ui::ProgressBar.new(value: 12, max: 12)
    class ProgressBar < Components::Base
      #: (value: untyped, ?max: untyped, ?label: untyped, ?tone: untyped, **untyped) -> void
      def initialize(value:, max: 100, label: nil, tone: :sage, **attrs)
        @value = value.to_f
        @max = [max.to_f, 1].max
        @label = label
        @tone = tone
        @attrs = attrs
      end

      #: () -> void
      def view_template
        div(class: "flex flex-col gap-2", **@attrs) do
          render_label if @label
          div(
            class: "h-1.5 w-full overflow-hidden rounded-full bg-surface-container-high",
            role: "progressbar",
            aria_valuenow: clamped_value,
            aria_valuemin: 0,
            aria_valuemax: @max.to_i
          ) do
            div(class: "h-full rounded-full #{fill}", style: "width: #{percent}%")
          end
        end
      end

      private

      #: () -> untyped
      def render_label
        div(class: "flex justify-between text-label-caps uppercase text-muted") do
          span { @label }
          span { "#{@value.to_i}/#{@max.to_i}" }
        end
      end

      #: () -> String
      def fill
        @tone == :terracotta ? "bg-secondary" : "bg-accent-sage"
      end

      # Clamp to the valid range so the visual width and the exposed
      # aria-valuenow stay consistent even when callers pass out-of-range values.

      #: () -> Integer
      def clamped_value
        @value.clamp(0, @max).round
      end

      #: () -> Integer
      def percent
        (clamped_value / @max * 100).round
      end
    end
  end
end
