# frozen_string_literal: true

module Components
  module Ui
    # Labelled text input — large, 20px-radius container on the card colour with
    # a sage focus ring and an I18n-driven error slot.
    #
    #   render Components::Ui::Field.new(name: "name", label: "Box name")
    class Field < Components::Base
      INPUT_BASE = "w-full rounded-card bg-card px-4 py-3 text-text-warm " \
                   "placeholder:text-muted transition focus:outline-none " \
                   "focus:ring-2 focus:ring-accent-sage/30"

      def initialize(name:, label:, type: "text", value: nil, placeholder: nil,
                     error: nil, hint: nil, required: false, **attrs)
        @name = name
        @label = label
        @type = type
        @value = value
        @placeholder = placeholder
        @error = error
        @hint = hint
        @required = required
        @attrs = attrs
      end

      def view_template
        div(class: "flex flex-col gap-2") do
          label(for: field_id, class: "text-label-caps uppercase text-muted") do
            @label
          end
          input(
            type: @type, name: @name, id: field_id, value: @value,
            placeholder: @placeholder, required: @required,
            class: input_classes, **@attrs
          )
          render_hint
          render_error
        end
      end

      private

      def render_hint
        return unless @hint && !@error

        p(class: "text-body-md text-on-surface-variant") { @hint }
      end

      def render_error
        return unless @error

        p(class: "text-body-md text-error", role: "alert") { @error }
      end

      def input_classes
        edge = @error ? "border border-error" : "border border-card-border focus:border-accent-sage"
        "#{INPUT_BASE} #{edge}"
      end

      def field_id
        @field_id ||= "field-#{@name.to_s.parameterize}"
      end
    end
  end
end
