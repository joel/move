# frozen_string_literal: true

module Components
  module Reviews
    # The walk's top row: exit-back arrow, progress label (+ fill bar in box
    # mode — omitted in queue mode, where the pending set shrinks as photos are
    # confirmed, so a bar over a moving total would be dishonest and the
    # "N more after this" count is the real progress), and the prev/next nav
    # arrows (#699). Every navigation here carries the pending-add guard
    # (#690) — typed-but-unsubmitted item text is auto-added before leaving.
    class ProgressBar < Components::Base
      # @rbs move: untyped
      # @rbs box: untyped
      # @rbs queue: untyped
      # @rbs queue_remaining: untyped
      # @rbs position: untyped
      # @rbs total: untyped
      # @rbs prev_href: untyped
      # @rbs next_href: untyped
      # @rbs return: void
      def initialize(move:, box:, queue:, queue_remaining:, position:, total:, prev_href:, next_href:)
        @move = move
        @box = box
        @queue = queue
        @queue_remaining = queue_remaining
        @position = position
        @total = total
        @prev_href = prev_href
        @next_href = next_href
      end

      #: () -> void
      def view_template
        div(class: "flex items-center gap-4") do
          exit_link
          div(class: "flex flex-1 flex-col gap-1") do
            span(class: "text-label-caps uppercase text-muted") { label }
            fill_bar unless @queue
          end
          render Components::Reviews::NavArrows.new(prev_href: @prev_href, next_href: @next_href)
        end
      end

      private

      # Exits the walk (to the queue page / the box) — not a prev-photo control.

      #: () -> untyped
      def exit_link
        a(
          href: @queue ? move_review_path(@move) : move_box_path(@move, @box),
          data: { action: "click->pending-add#guardVisit" },
          class: "flex h-10 w-10 items-center justify-center rounded-full bg-card text-muted hover:text-text-warm"
        ) { render Components::Icons::ChevronRight.new(css: "h-5 w-5 rotate-180") }
      end

      #: () -> String
      def label
        if @queue
          I18n.t("reviews.photo.queue_progress", count: @queue_remaining)
        else
          I18n.t("reviews.photo.progress", position: @position, total: @total)
        end
      end

      #: () -> untyped
      def fill_bar
        div(class: "h-1.5 w-full overflow-hidden rounded-full bg-surface-container-high") do
          div(class: "h-full rounded-full bg-accent-sage", style: "width: #{pct}%")
        end
      end

      #: () -> Integer
      def pct
        return 0 if @total.zero?

        ((@position.to_f / @total) * 100).round
      end
    end
  end
end
