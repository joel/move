# frozen_string_literal: true

module Views
  module Reviews
    # C1 — Review Queue. Per-box summary (pending / needs-correction / auto-confirmed)
    # and a queue of unresolved suggestions (lowest confidence first), each with a
    # full media thumbnail and inline Keep / Correct. "Start Review" enters C2.
    class Queue < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(move:, box:, queue:, counts:, first_unreviewed:)
        @move = move
        @box = box
        @queue = queue
        @counts = counts
        @first = first_unreviewed
      end

      def view_template
        back_link
        header
        summary
        queue_section
      end

      private

      def back_link
        a(href: move_box_path(@move, @box),
          class: "inline-flex items-center gap-2 text-label-caps uppercase text-muted hover:text-text-warm") do
          render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-180")
          plain I18n.t("reviews.queue.back", number: box_number)
        end
      end

      def header
        render Components::Ui::SectionHeader.new(
          title: I18n.t("reviews.queue.title"),
          subtitle: I18n.t("reviews.queue.subtitle", number: box_number)
        ) do
          if @first
            render Components::Ui::Button.new(
              label: I18n.t("reviews.queue.start"), href: move_box_review_path(@move, @box, @first)
            )
          end
        end
      end

      def summary
        div(class: "grid grid-cols-1 gap-stack-gap sm:grid-cols-3") do
          stat_card(:pending, @counts[:pending], "text-tertiary")
          stat_card(:needs_correction, @counts[:needs_correction], "text-secondary")
          stat_card(:auto_confirmed, @counts[:auto_confirmed], "text-accent-sage")
        end
      end

      def stat_card(key, count, accent)
        render Components::Ui::Card.new(padding: "p-5") do
          p(class: "text-label-caps uppercase #{accent}") { I18n.t("reviews.queue.stats.#{key}") }
          p(class: "text-headline-xl text-text-warm") { count.to_s }
          p(class: "text-body-md text-muted") { I18n.t("reviews.queue.items", count: count) }
        end
      end

      def queue_section
        section(class: "flex flex-col gap-stack-gap") do
          div(class: "flex items-center justify-between px-2") do
            h3(class: "text-headline-md text-text-warm") { I18n.t("reviews.queue.heading") }
            span(class: "text-label-caps uppercase text-muted") do
              I18n.t("reviews.queue.showing", count: @queue.size)
            end
          end
          @queue.any? ? rows : empty_state
        end
      end

      def rows
        div(class: "flex flex-col gap-stack-gap") do
          @queue.each { |suggestion| row(suggestion) }
        end
      end

      def row(suggestion)
        render Components::Ui::Card.new(padding: "p-4", class: row_accent(suggestion)) do
          div(class: "flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between") do
            div(class: "flex items-center gap-4") do
              thumb(suggestion)
              identity(suggestion)
            end
            div(class: "flex items-center gap-2") do
              render Components::Ui::RecognitionState.new(state: suggestion_state(suggestion))
              actions(suggestion)
            end
          end
        end
      end

      def thumb(suggestion)
        div(class: "h-16 w-16 shrink-0 overflow-hidden rounded-xl bg-surface-container-high " \
                   "flex items-center justify-center text-muted") do
          if suggestion.media&.image&.attached?
            img(src: view_context.rails_storage_proxy_path(suggestion.media.image),
                class: "h-full w-full object-cover", alt: "", loading: "lazy")
          else
            render Components::Icons::Camera.new(css: "h-6 w-6")
          end
        end
      end

      def identity(suggestion)
        div(class: "flex flex-col gap-1") do
          span(class: "text-body-lg text-text-warm") { suggestion.proposed_name }
          div(class: "flex items-center gap-2 text-label-caps uppercase text-muted") do
            span { @box.room.name } if @box.room
            span { confidence_label(suggestion) }
          end
        end
      end

      def actions(suggestion)
        button_to(I18n.t("reviews.actions.keep"), keep_move_box_review_path(@move, @box, suggestion),
                  method: :patch, class: pill(:sage))
        button_to(I18n.t("reviews.actions.correct"), correct_move_box_review_path(@move, @box, suggestion),
                  method: :patch, class: pill(:ghost))
      end

      def empty_state
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Check,
          title: I18n.t("reviews.queue.empty_title"),
          description: I18n.t("reviews.queue.empty_description")
        )
      end

      # Conflicts get a terracotta hairline to flag they need a human decision.
      def row_accent(suggestion)
        suggestion.conflict? ? "border-secondary" : ""
      end

      def suggestion_state(suggestion)
        suggestion.conflict? ? "needs_correction" : "pending_review"
      end

      def confidence_label(suggestion)
        return I18n.t("reviews.confidence.unknown") if suggestion.confidence_score.nil?

        high = suggestion.confidence_score >= @move.auto_confirm_threshold
        I18n.t("reviews.confidence.#{high ? "high" : "low"}")
      end

      def pill(variant)
        base = "inline-flex items-center justify-center gap-1 rounded-full px-4 py-2 " \
               "text-sm font-bold transition active:scale-[0.98]"
        tint = variant == :sage ? "bg-accent-sage text-page hover:opacity-90" : "text-text-warm hover:bg-surface-container-high"
        "#{base} #{tint}"
      end

      def box_number
        Kernel.format("%03d", @box.number.to_i)
      end
    end
  end
end
