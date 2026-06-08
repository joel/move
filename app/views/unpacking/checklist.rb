# frozen_string_literal: true

module Views
  module Unpacking
    # E3 — Unpacking Mode, active checklist. A focused single column: box header,
    # a sticky progress card (remaining count), the remaining in-box items as
    # large remove tap-targets, a dimmed "Unpacked" section whose rows restore on
    # tap, and the "Mark box unpacked" CTA. Read-only when the Move is archived.
    # Renders inside the AppShellLayout.
    class Checklist < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(move:, box:, remaining:, unpacked:)
        @move = move
        @box = box
        @remaining = remaining.to_a
        @unpacked = unpacked.to_a
      end

      def view_template
        div(class: "mx-auto flex w-full max-w-2xl flex-col gap-section-gap") do
          back_link
          header
          progress_card
          remaining_section
          unpacked_section if @unpacked.any?
          complete_cta if writable?
        end
      end

      private

      def writable? = @move.writable?

      def total = @remaining.size + @unpacked.size

      def back_link
        a(
          href: move_box_path(@move, @box),
          class: "inline-flex items-center gap-2 text-label-caps uppercase text-muted hover:text-text-warm"
        ) do
          render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-180")
          plain I18n.t("unpacking.back")
        end
      end

      def header
        div(class: "flex flex-col gap-3") do
          div(class: "flex flex-wrap gap-2") { chips }
          h1(class: "text-headline-xl text-text-warm") { box_title }
        end
      end

      def chips
        render Components::Ui::Chip.new(label: @box.room.name, kind: :room) if @box.room
        render Components::Ui::Chip.new(label: I18n.t("unpacking.read_only"), kind: :tag) unless writable?
      end

      # Sticky so the remaining count stays in view while the list scrolls
      # (D10 §6 "sticky remaining-count"). Sits below the mobile top bar.
      def progress_card
        div(class: "sticky top-20 z-10 lg:top-4") do
          render Components::Ui::Card.new(padding: "p-4") do
            div(class: "flex items-center justify-between") do
              span(class: "text-body-lg text-text-warm") { I18n.t("unpacking.progress") }
              span(class: "text-body-md text-accent-sage") do
                I18n.t("unpacking.remaining_count", count: @remaining.size, total:)
              end
            end
            render Components::Ui::ProgressBar.new(value: @unpacked.size, max: [total, 1].max)
          end
        end
      end

      def remaining_section
        section(class: "flex flex-col gap-stack-gap") do
          h2(class: "text-headline-md text-text-warm") { I18n.t("unpacking.remaining_title") }
          if @remaining.any?
            @remaining.each { |item| remaining_row(item) }
          else
            all_clear
          end
        end
      end

      def remaining_row(item)
        if writable?
          button_to(
            move_box_unpacking_remove_path(@move, @box, item),
            method: :patch, class: "#{row_classes} hover:bg-surface-container-high"
          ) { remaining_row_body(item) }
        else
          div(class: row_classes) { remaining_row_body(item) }
        end
      end

      def remaining_row_body(item)
        empty_circle
        item_text(item)
      end

      def unpacked_section
        section(class: "flex flex-col gap-stack-gap") do
          h2(class: "flex items-center gap-2 text-headline-md text-muted") do
            render Components::Icons::Check.new(css: "h-5 w-5")
            plain I18n.t("unpacking.unpacked_title")
          end
          div(class: "flex flex-col gap-stack-gap opacity-70") do
            @unpacked.each { |item| unpacked_row(item) }
          end
        end
      end

      def unpacked_row(item)
        if writable?
          button_to(
            move_box_unpacking_restore_path(@move, @box, item),
            method: :patch, class: "#{row_classes} hover:opacity-100",
            aria_label: I18n.t("unpacking.restore", name: item.name)
          ) { unpacked_row_body(item) }
        else
          div(class: row_classes) { unpacked_row_body(item) }
        end
      end

      def unpacked_row_body(item)
        filled_circle
        item_text(item, struck: true)
      end

      def item_text(item, struck: false)
        strike = struck ? " line-through" : ""
        div(class: "flex-1 text-left") do
          span(class: "block text-body-lg text-text-warm#{strike}") { item_label(item) }
          if (subtitle = item_subtitle(item))
            span(class: "block text-body-md text-muted#{strike}") { subtitle }
          end
        end
      end

      def empty_circle
        div(class: "flex h-8 w-8 shrink-0 items-center justify-center rounded-full " \
                   "border-2 border-muted transition")
      end

      def filled_circle
        div(class: "flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-accent-sage text-page") do
          render Components::Icons::Check.new(css: "h-5 w-5")
        end
      end

      # The "Mark box unpacked" action — cascades every remaining in-box item to
      # removed. In-flow (not a second fixed bar) so it coexists with the shell's
      # mobile bottom tab bar.
      def complete_cta
        button_to(
          move_box_unpacking_complete_path(@move, @box),
          method: :patch,
          class: "inline-flex w-full items-center justify-center gap-2 rounded-full bg-accent-sage " \
                 "px-6 py-4 text-body-lg font-bold text-page transition hover:opacity-90 active:scale-[0.98]",
          data: { turbo_confirm: I18n.t("unpacking.complete_confirm") }
        ) do
          render Components::Icons::Check.new(css: "h-5 w-5")
          plain I18n.t("unpacking.complete")
        end
      end

      def all_clear
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Check,
          title: I18n.t("unpacking.all_clear_title"),
          description: I18n.t("unpacking.all_clear_description")
        )
      end

      def row_classes
        "group flex w-full items-center gap-4 rounded-card border border-card-border " \
          "bg-card p-4 transition active:scale-[0.98]"
      end

      def item_label(item)
        item.quantity > 1 ? "#{item.name} ×#{item.quantity}" : item.name
      end

      def item_subtitle(item)
        item.category&.name
      end

      def box_title
        I18n.t("unpacking.box_title", number: Kernel.format("%03d", @box.number.to_i))
      end
    end
  end
end
