# frozen_string_literal: true

module Components
  module Ui
    # Single source of truth for the seven recognition states (reused by the
    # capture / review / box surfaces in later phases). Each state has a fixed
    # treatment: processing pulses a sage glow; failed gets a terracotta border
    # plus an optional Retry overlay.
    #
    #   render Components::Ui::RecognitionState.new(state: :processing)
    #   render Components::Ui::RecognitionState.new(state: :failed, retry_href: "/retry")
    class RecognitionState < Components::Base
      STATES = {
        queued: {
          icon: Components::Icons::Clock,
          classes: "bg-surface-container-high text-muted"
        },
        processing: {
          icon: Components::Icons::Sparkles,
          classes: "bg-accent-sage/15 text-accent-sage ui-pulse-glow"
        },
        succeeded: {
          icon: Components::Icons::Check,
          classes: "bg-accent-sage/15 text-accent-sage"
        },
        failed: {
          icon: Components::Icons::Alert,
          classes: "bg-error-container/30 text-error border border-error"
        },
        needs_correction: {
          icon: Components::Icons::Pencil,
          classes: "bg-secondary/15 text-secondary"
        },
        auto_confirmed: {
          icon: Components::Icons::Bolt,
          classes: "border border-accent-sage text-accent-sage bg-transparent"
        },
        pending_review: {
          icon: Components::Icons::Eye,
          classes: "bg-tertiary/15 text-tertiary"
        }
      }.freeze

      #: (state: untyped, ?retry_href: untyped, **untyped) -> void
      def initialize(state:, retry_href: nil, **attrs)
        @state = state.to_sym
        @config = STATES.fetch(@state) do
          raise ArgumentError, "Unknown recognition state: #{state.inspect}"
        end
        @retry_href = retry_href
        @attrs = attrs
      end

      #: () -> void
      def view_template
        span(class: badge_classes, **@attrs) do
          render @config[:icon].new(css: "h-4 w-4")
          span { I18n.t("ui.states.#{@state}") }
          render_retry if @state == :failed && @retry_href
        end
      end

      private

      #: () -> untyped
      def render_retry
        a(
          href: @retry_href,
          class: "ml-1 rounded-full bg-error px-2 py-0.5 text-on-error " \
                 "text-label-caps uppercase"
        ) { I18n.t("ui.buttons.retry") }
      end

      #: () -> String
      def badge_classes
        [
          "inline-flex items-center gap-1.5 rounded-full px-3 py-1",
          "text-label-caps uppercase",
          @config[:classes]
        ].join(" ")
      end
    end
  end
end
