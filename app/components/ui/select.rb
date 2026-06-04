# frozen_string_literal: true

module Components
  module Ui
    # Labelled select — matches Ui::Field shaping. `options:` is an array of
    # [label, value] pairs (value defaults to label when omitted).
    #
    #   render Components::Ui::Select.new(
    #     name: "unit", label: "Unit system",
    #     options: [["Metric", "metric"], ["Imperial", "imperial"]]
    #   )
    class Select < Components::Base
      def initialize(name:, label:, options: [], selected: nil, error: nil, **attrs)
        @name = name
        @label = label
        @options = options
        @selected = selected
        @error = error
        @attrs = attrs
      end

      def view_template
        div(class: "flex flex-col gap-2") do
          label(for: field_id, class: "text-label-caps uppercase text-muted") do
            @label
          end
          select(name: @name, id: field_id, class: classes, **@attrs) do
            @options.each do |opt|
              text, value = Array(opt)
              value ||= text
              option(value: value, selected: (value.to_s == @selected.to_s)) { text }
            end
          end
          p(class: "text-body-md text-error", role: "alert") { @error } if @error
        end
      end

      private

      def classes
        edge = @error ? "border border-error" : "border border-card-border focus:border-accent-sage"
        "w-full rounded-card bg-card px-4 py-3 text-text-warm transition " \
          "focus:outline-none focus:ring-2 focus:ring-accent-sage/30 #{edge}"
      end

      def field_id
        @field_id ||= "select-#{@name.to_s.parameterize}"
      end
    end
  end
end
