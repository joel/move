# frozen_string_literal: true

module Components
  module Unpacking
    # E3 — the sticky progress card (remaining count + progress bar). Extracted
    # with a stable id so UnpackingController can Turbo-Stream-replace just this
    # region after each remove/restore tap, without re-rendering the checklist.
    class ProgressCard < Components::Base
      ID = "unpacking-progress-card"

      #: (remaining_count: untyped, total: untyped) -> void
      def initialize(remaining_count:, total:)
        @remaining_count = remaining_count
        @total = total
      end

      #: () -> void
      def view_template
        # Sticky so the remaining count stays in view while the list scrolls
        # (D10 §6). Sits below the mobile top bar.
        div(id: ID, class: "sticky top-20 z-10 lg:top-4") do
          render Components::Ui::Card.new(padding: "p-4") do
            div(class: "flex items-center justify-between") do
              span(class: "text-body-lg text-text-warm") { I18n.t("unpacking.progress") }
              span(class: "text-body-md text-accent-sage") do
                I18n.t("unpacking.remaining_count", count: @remaining_count, total: @total)
              end
            end
            render Components::Ui::ProgressBar.new(value: @total - @remaining_count, max: [@total, 1].max)
          end
        end
      end
    end
  end
end
