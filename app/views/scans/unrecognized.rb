# frozen_string_literal: true

module Views
  module Scans
    # E2 — unrecognized state. Shown for a token that isn't a box in this Move's
    # tenant (unknown, malformed, or a foreign org's label). The copy is
    # deliberately non-disclosing — it never hints the token exists elsewhere —
    # and offers a retry back to the scanner.
    class Unrecognized < Views::Base
      def initialize(move:)
        @move = move
      end

      def view_template
        render Components::Ui::Card.new(padding: "p-8", class: "mx-auto w-full max-w-md text-center") do
          div(class: "mx-auto mb-4 flex h-14 w-14 items-center justify-center rounded-full " \
                     "bg-secondary/15 text-secondary") do
            render Components::Icons::Alert.new(css: "h-7 w-7")
          end
          h2(class: "text-headline-md text-text-warm") { I18n.t("scans.unrecognized.title") }
          p(class: "mt-2 text-body-md text-muted") { I18n.t("scans.unrecognized.body") }
          div(class: "mt-6") do
            render Components::Ui::Button.new(
              label: I18n.t("scans.unrecognized.retry"), variant: :terracotta,
              full_width: true, href: move_scan_path(@move)
            )
          end
        end
      end
    end
  end
end
