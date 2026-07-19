# frozen_string_literal: true

module Components
  module Ui
    # Pill-shaped button. Renders an <a> when `href:` is given, otherwise a
    # <button>. Pressed state "sinks" (scale 0.98) per the design system.
    #
    #   render Components::Ui::Button.new(label: "Save")
    #   render Components::Ui::Button.new(label: "Cancel", variant: :ghost, href: "/")
    class Button < Components::Base
      VARIANTS = {
        # Primary: sage fill, dark page-coloured text (Boxes Home reference).
        primary: "bg-accent-sage text-page hover:opacity-90",
        # Secondary: sage outline, transparent fill.
        secondary: "border border-accent-sage text-accent-sage bg-transparent " \
                   "hover:bg-accent-sage/10",
        # Terracotta: highlights / Fragile (secondary semantic colour).
        terracotta: "bg-secondary text-on-secondary hover:opacity-90",
        # Ghost: chromeless, surface hover.
        ghost: "bg-transparent text-text-warm hover:bg-surface-container-high",
        # Danger: destructive actions.
        danger: "bg-error text-on-error hover:opacity-90"
      }.freeze

      # The pill recipe as a plain class string — for form helpers (button_to /
      # submit buttons) that can't render the component but must not fork the
      # recipe (#702; hand-rolled copies kept dropping select-none and the
      # focus-visible ring). Singleton defs aren't supported by inline RBS;
      # declared in sig/component_singletons.rbs.

      # @rbs skip
      def self.classes(variant: :primary, full_width: false)
        [
          "inline-flex items-center justify-center gap-2 rounded-full",
          "px-6 py-3 text-sm font-bold transition select-none",
          "active:scale-[0.98] focus-visible:outline-2",
          "focus-visible:outline-offset-2 focus-visible:outline-accent-sage",
          "disabled:opacity-50 disabled:pointer-events-none",
          VARIANTS.fetch(variant, VARIANTS[:primary]),
          (full_width ? "w-full" : nil)
        ].compact.join(" ")
      end

      #: (?label: untyped, ?variant: untyped, ?href: untyped, ?type: untyped, ?full_width: untyped, ?icon: untyped, ?disabled: untyped, **untyped) -> void
      def initialize(
        label: nil, variant: :primary, href: nil, type: "button",
        full_width: false, icon: nil, disabled: false, **attrs
      )
        @label = label
        @variant = variant
        @href = href
        @type = type
        @full_width = full_width
        @icon = icon
        @disabled = disabled
        @attrs = attrs
      end

      #: () ?{ (*untyped) -> untyped } -> untyped
      def view_template(&)
        if @href && !@disabled
          a(href: @href, class: classes, **@attrs) { contents(&) }
        else
          button(type: @type, disabled: @disabled, class: classes, **@attrs) do
            contents(&)
          end
        end
      end

      private

      #: () ?{ (*untyped) -> untyped } -> untyped
      def contents(&block)
        render(@icon.new(css: "h-5 w-5")) if @icon
        if block
          yield
        elsif @label
          span { @label }
        end
      end

      #: () -> String
      def classes
        self.class.classes(variant: @variant, full_width: @full_width)
      end
    end
  end
end
