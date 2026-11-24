# frozen_string_literal: true

module Components
  module Ui
    # Icon-only navigation button (#696) — the round chevron/pencil control on
    # the box-detail header, the box-to-box arrows and the review walk. The icon
    # is the block. Given an `href:` it renders an anchor; given nil it renders
    # a same-size faded span so a cluster of arrows never shifts as one comes
    # and goes along a walk. The disabled span keeps the label plus a link role
    # (aria-disabled needs a role to announce) and tabindex="0" (the APG
    # disabled-link pattern) so the boundary stays perceivable to assistive
    # tech and keyboard users.
    #
    #   render Components::Ui::IconButton.new(href: next_path, label: "Next box") do
    #     render Components::Icons::ChevronRight.new(css: "h-5 w-5")
    #   end
    #
    # `data:` lands on the anchor only (e.g. the review walk's pending-add
    # guard); a disabled span has nothing to guard. `variant:` — :ghost (bare,
    # hover fill) or :filled (a 40px card-filled circle).
    class IconButton < Components::Base
      VARIANTS = {
        ghost: "rounded-full p-2 text-muted transition hover:bg-surface-container-high hover:text-text-warm",
        filled: "flex h-10 w-10 items-center justify-center rounded-full bg-card text-muted hover:text-text-warm"
      }.freeze
      DISABLED = {
        ghost: "rounded-full p-2 text-muted/40",
        filled: "flex h-10 w-10 items-center justify-center rounded-full bg-card text-muted/40"
      }.freeze

      # @rbs href: String? -- nil renders the disabled span
      # @rbs label: String? -- the accessible name (icon-only, so pass one)
      # @rbs data: Hash[Symbol, untyped]
      # @rbs variant: Symbol
      # @rbs return: void
      def initialize(href:, label: nil, data: {}, variant: :ghost)
        @href = href
        @label = label
        @data = data
        @variant = variant
      end

      #: () ?{ (*untyped) -> untyped } -> untyped
      def view_template(&)
        if @href
          a(href: @href, aria_label: @label, data: @data, class: VARIANTS.fetch(@variant), &)
        else
          span(role: "link", tabindex: "0", aria_disabled: "true", aria_label: @label,
               class: DISABLED.fetch(@variant), &)
        end
      end
    end
  end
end
