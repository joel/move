# frozen_string_literal: true

module Views
  module Scans
    # E2 — resolved state. Reveals box identity only (number + room) plus an item
    # count and current status — never the contents themselves (Domain §12). The
    # "Open box" CTA leads to the box detail, where authorized members see the
    # full inventory. Status is shown, never changed by the scan.
    class Resolved < Views::Base
      def initialize(move:, box:)
        @move = move
        @box = box
      end

      def view_template
        render Components::Ui::Card.new(padding: "p-6", class: "mx-auto w-full max-w-md") do
          identity
          tiles
          open_button
        end
      end

      private

      def identity
        div(class: "flex items-start justify-between gap-3") do
          div(class: "flex flex-col gap-2") do
            h2(class: "text-headline-xl text-text-warm") { box_title }
            div(class: "flex items-center gap-2 text-sm text-accent-sage") do
              render Components::Icons::Check.new(css: "h-4 w-4")
              plain I18n.t("scans.resolved.success")
            end
          end
          render(Components::Ui::Chip.new(label: @box.room.name, kind: :room)) if @box.room
        end
      end

      def tiles
        div(class: "mt-6 grid grid-cols-2 gap-3") do
          tile(I18n.t("scans.resolved.items"), @box.item_count.to_s)
          tile(I18n.t("scans.resolved.status"), I18n.t("boxes.status.#{@box.status}"))
        end
      end

      def tile(label, value)
        div(class: "rounded-card border border-card-border bg-surface-container-high p-4") do
          p(class: "text-headline-md text-text-warm") { value }
          p(class: "text-label-caps uppercase text-muted") { label }
        end
      end

      def open_button
        div(class: "mt-6") do
          render Components::Ui::Button.new(
            label: I18n.t("scans.resolved.open"), full_width: true,
            href: move_box_path(@box.move, @box)
          )
        end
      end

      def box_title
        "Box ##{Kernel.format("%03d", @box.number.to_i)}"
      end
    end
  end
end
