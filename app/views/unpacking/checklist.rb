# frozen_string_literal: true

module Views
  module Unpacking
    # E3 — Unpacking Mode, active checklist. A focused single column: box header,
    # a sticky progress card (remaining count), the remaining in-box items as
    # large remove tap-targets, a dimmed "Unpacked" section whose rows restore on
    # tap, and the "Mark box unpacked" CTA. Read-only when the Move is archived.
    # Renders inside the AppShellLayout.
    #
    # The progress card, the two sections and their rows are extracted into
    # stable-id Components::Unpacking::* so UnpackingController can stream just the
    # affected regions on each remove/restore tap — no full-page reload (#378).
    class Checklist < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(move:, box:, remaining:, unpacked:, editable: false)
        @move = move
        @box = box
        @remaining = remaining.to_a
        @unpacked = unpacked.to_a
        @editable = editable
      end

      def view_template
        div(class: "mx-auto flex w-full max-w-2xl flex-col gap-section-gap") do
          back_link
          header
          render Components::Unpacking::ProgressCard.new(remaining_count: @remaining.size, total: total)
          render Components::Unpacking::RemainingSection.new(
            remaining: @remaining, move: @move, box: @box, editable: editable?
          )
          render Components::Unpacking::UnpackedSection.new(
            unpacked: @unpacked, move: @move, box: @box, editable: editable?
          )
          complete_cta if editable?
        end
      end

      private

      # Mutating affordances show only for an editor on a writable Move — viewers
      # (and archived Moves) see the checklist read-only. The server still 403s.
      def editable? = @editable

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
        render Components::Ui::Chip.new(label: I18n.t("unpacking.read_only"), kind: :tag) unless editable?
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

      def box_title
        I18n.t("unpacking.box_title", number: Kernel.format("%03d", @box.number.to_i))
      end
    end
  end
end
