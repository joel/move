# frozen_string_literal: true

module Components
  module Ui
    # Pill-shaped progress bar with a sage fill (boxes packed / items reviewed).
    #
    #   render Components::Ui::ProgressBar.new(value: 12, max: 12)
    class ProgressBar < Components::Base
      def initialize(value:, max: 100, label: nil, tone: :sage, **attrs)
        @value = value.to_f
        @max = [max.to_f, 1].max
        @label = label
        @tone = tone
        @attrs = attrs
      end

      def view_template
        div(class: "flex flex-col gap-2", **@attrs) do
          render_label if @label
          div(
            class: "h-1.5 w-full overflow-hidden rounded-full bg-surface-container-high",
            role: "progressbar",
            aria_valuenow: @value.to_i,
            aria_valuemin: 0,
            aria_valuemax: @max.to_i
          ) do
            div(class: "h-full rounded-full #{fill}", style: "width: #{percent}%")
          end
        end
      end

      private

      def render_label
        div(class: "flex justify-between text-label-caps uppercase text-muted") do
          span { @label }
          span { "#{@value.to_i}/#{@max.to_i}" }
        end
      end

      def fill
        @tone == :terracotta ? "bg-secondary" : "bg-accent-sage"
      end

      def percent
        ((@value / @max) * 100).clamp(0, 100).round
      end
    end
  end
end
