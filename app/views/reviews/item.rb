# frozen_string_literal: true

module Views
  module Reviews
    # C2 — Review item-by-item. One suggestion at a time (lowest confidence first):
    # full media, confidence, proposed name/quantity/fragile, and the three core
    # actions Keep / Correct / Ignore. Progress shows position in the review set.
    class Item < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(move:, box:, suggestion:, position:, total:)
        @move = move
        @box = box
        @suggestion = suggestion
        @position = position
        @total = total
      end

      def view_template
        progress_bar
        div(class: "grid grid-cols-1 gap-stack-gap lg:grid-cols-12") do
          media_panel
          decision_panel
        end
      end

      private

      def progress_bar
        div(class: "flex items-center gap-4") do
          a(href: move_box_review_index_path(@move, @box),
            class: "flex h-10 w-10 items-center justify-center rounded-full bg-card text-muted hover:text-text-warm") do
            render Components::Icons::ChevronRight.new(css: "h-5 w-5 rotate-180")
          end
          div(class: "flex flex-1 flex-col gap-1") do
            span(class: "text-label-caps uppercase text-muted") do
              I18n.t("reviews.item.progress", position: @position, total: @total)
            end
            div(class: "h-1.5 w-full overflow-hidden rounded-full bg-surface-container-high") do
              div(class: "h-full rounded-full bg-accent-sage", style: "width: #{progress_pct}%")
            end
          end
        end
      end

      def media_panel
        section(class: "lg:col-span-7") do
          div(class: "overflow-hidden rounded-card border border-card-border bg-surface-container-high") do
            if @suggestion.media&.image&.attached?
              img(src: view_context.rails_storage_proxy_path(@suggestion.media.image),
                  class: "aspect-square w-full object-cover", alt: "", loading: "lazy")
            else
              div(class: "flex aspect-square w-full items-center justify-center text-muted") do
                render Components::Icons::Camera.new(css: "h-10 w-10")
              end
            end
          end
        end
      end

      def decision_panel
        section(class: "lg:col-span-5") do
          render Components::Ui::Card.new(padding: "p-6") do
            confidence_badge
            h2(class: "text-headline-lg text-text-warm") { @suggestion.proposed_name }
            chips
            quantity
            actions
          end
        end
      end

      def confidence_badge
        render Components::Ui::RecognitionState.new(state: @suggestion.conflict? ? "needs_correction" : "pending_review")
        if (pct = @suggestion.confidence_percent)
          span(class: "ml-2 text-label-caps uppercase text-muted") do
            I18n.t("reviews.item.confidence", percent: pct)
          end
        end
      end

      def chips
        div(class: "flex flex-wrap gap-2") do
          render Components::Ui::Chip.new(label: @box.room.name, kind: :room) if @box.room
          render Components::Ui::Chip.new(label: I18n.t("reviews.item.fragile"), kind: :tag) if @suggestion.proposed_fragile
        end
      end

      def quantity
        div(class: "flex items-center justify-between rounded-card bg-card px-4 py-3") do
          span(class: "text-label-caps uppercase text-muted") { I18n.t("reviews.item.quantity") }
          span(class: "text-body-lg font-bold tabular-nums text-text-warm") { @suggestion.proposed_quantity.to_s }
        end
      end

      def actions
        div(class: "flex flex-col gap-3") do
          button_to(I18n.t("reviews.actions.keep"), keep_move_box_review_path(@move, @box, @suggestion),
                    method: :patch, class: action_pill(:sage, full: true))
          div(class: "grid grid-cols-2 gap-3") do
            button_to(I18n.t("reviews.actions.correct"), correct_move_box_review_path(@move, @box, @suggestion),
                      method: :patch, class: action_pill(:ghost))
            button_to(I18n.t("reviews.actions.ignore"), mark_false_positive_move_box_review_path(@move, @box, @suggestion),
                      method: :patch, class: action_pill(:ghost),
                      data: { turbo_confirm: I18n.t("reviews.item.ignore_confirm") })
          end
        end
      end

      def action_pill(variant, full: false)
        base = "inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 " \
               "text-sm font-bold transition active:scale-[0.98]"
        tint = if variant == :sage
                 "bg-accent-sage text-page hover:opacity-90"
               else
                 "border border-card-border text-text-warm hover:bg-surface-container-high"
               end
        [base, tint, (full ? "w-full" : nil)].compact.join(" ")
      end

      def progress_pct
        return 0 if @total.zero?

        ((@position.to_f / @total) * 100).round
      end
    end
  end
end
