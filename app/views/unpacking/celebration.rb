# frozen_string_literal: true

module Views
  module Unpacking
    # E3 — Unpacking Mode, box-unpacked celebration. A calm, centred confirmation
    # shown once the box reaches `unpacked`: a large check, the reassurance copy,
    # "Back to boxes", and an "Undo" that reopens the box (unpacked -> unpacking)
    # so removed items can be restored individually. Renders in the AppShellLayout.
    class Celebration < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(move:, box:)
        @move = move
        @box = box
      end

      def view_template
        div(class: "mx-auto flex min-h-[60vh] w-full max-w-md flex-col items-center justify-center gap-section-gap text-center") do
          identity
          check
          copy
          actions
        end
      end

      private

      def identity
        div(class: "flex items-center gap-3") do
          span(class: "text-label-caps uppercase tracking-widest text-muted") { box_label }
          render(Components::Ui::Chip.new(label: @box.room.name, kind: :room)) if @box.room
        end
      end

      def check
        div(class: "relative") do
          div(class: "absolute inset-0 rounded-full bg-accent-sage/20 blur-2xl")
          div(class: "relative flex h-28 w-28 items-center justify-center rounded-full " \
                     "border-4 border-accent-sage text-accent-sage") do
            render Components::Icons::Check.new(css: "h-16 w-16")
          end
        end
      end

      def copy
        div(class: "flex flex-col gap-3") do
          h1(class: "text-headline-xl text-text-warm") { I18n.t("unpacking.done_title") }
          p(class: "mx-auto max-w-[280px] text-body-lg text-muted") { I18n.t("unpacking.done_body") }
        end
      end

      def actions
        div(class: "flex w-full flex-col items-center gap-stack-gap") do
          render Components::Ui::Button.new(
            label: I18n.t("unpacking.back_to_boxes"), full_width: true,
            href: move_boxes_path(@move)
          )
          undo_button if @move.writable?
        end
      end

      def undo_button
        button_to(
          move_box_unpacking_reopen_path(@move, @box),
          method: :patch,
          class: "rounded-full px-6 py-3 text-label-caps uppercase tracking-widest text-muted " \
                 "transition hover:text-text-warm active:scale-[0.98]"
        ) { plain I18n.t("unpacking.undo") }
      end

      def box_label
        I18n.t("unpacking.box_title", number: Kernel.format("%03d", @box.number.to_i))
      end
    end
  end
end
