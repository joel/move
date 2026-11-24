# frozen_string_literal: true

module Components
  module Ui
    # Compact pill select (#696) — the label-less inline control used where a
    # visible label would be noise (a member's role on the roster row, the box
    # detail's jump-to-box). With no visible label, `aria_label:` is required so
    # the control stays named for assistive tech. `options:` is an array of
    # [label, value] pairs, as in Ui::Select; `selected:` compares by `to_s`.
    #
    # `auto_submit: true` wires the select's change event to the auto-submit
    # Stimulus controller, which submits the ENCLOSING form — so the caller's
    # form must carry `data: { controller: "auto-submit" }`:
    #
    #   form_with(url: ..., data: { controller: "auto-submit" }) do
    #     render Components::Ui::CompactSelect.new(
    #       name: "member[role]", aria_label: "Change role",
    #       options: [["Admin", "admin"], ["Viewer", "viewer"]],
    #       selected: "viewer", auto_submit: true
    #     )
    #   end
    class CompactSelect < Components::Base
      CLASSES = "cursor-pointer appearance-none rounded-full border border-card-border " \
                "bg-card py-2 pl-4 pr-9 text-body-md text-text-warm transition " \
                "hover:border-accent-sage focus:outline-none focus:ring-2 focus:ring-accent-sage/30"

      # @rbs name: String
      # @rbs aria_label: String
      # @rbs options: Array[[untyped, untyped]]
      # @rbs selected: untyped
      # @rbs auto_submit: bool
      # @rbs return: void
      def initialize(name:, aria_label:, options:, selected: nil, auto_submit: false)
        @name = name
        @aria_label = aria_label
        @options = options
        @selected = selected
        @auto_submit = auto_submit
      end

      #: () -> void
      def view_template
        div(class: "relative") do
          select(name: @name, aria_label: @aria_label, data: select_data, class: CLASSES) do
            @options.each do |text, value|
              option(value: value, selected: value.to_s == @selected.to_s) { text }
            end
          end
          chevron
        end
      end

      private

      #: () -> Hash[Symbol, String]
      def select_data
        @auto_submit ? { action: "change->auto-submit#submit" } : {}
      end

      #: () -> void
      def chevron
        span(
          class: "pointer-events-none absolute inset-y-0 right-3 flex items-center " \
                 "text-on-surface-variant"
        ) { render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-90") }
      end
    end
  end
end
