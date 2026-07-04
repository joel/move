# frozen_string_literal: true

module Views
  module BoxSteps
    # Phase 44 — Bulk box lifecycle steps. An editor-only page (reached from the
    # Menu) showing the current box state distribution and, for each forward step
    # that has boxes waiting, a confirm-guarded button that advances every box in
    # that source state. Rendered from project tokens (dark-first), mirroring the
    # F2 Summary surface. Counts come pre-computed from a single SQL GROUP BY.
    class Show < Views::Base
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::Routes

      # `counts` is { status => count } from move.boxes.group(:status).count;
      # `steps` is the already-filtered list of { from:, to: } whose source state
      # is non-empty (so a card only appears when it can do something).

      #: (move: untyped, counts: untyped, steps: untyped) -> void
      def initialize(move:, counts:, steps:)
        @move = move
        @counts = counts
        @steps = steps
      end

      #: () -> void
      def view_template
        div(class: "flex flex-col gap-section-gap") do
          render Components::Ui::SectionHeader.new(
            eyebrow: @move.name,
            title: I18n.t("box_steps.show.title"),
            subtitle: I18n.t("box_steps.show.subtitle")
          )
          distribution
          if @steps.empty?
            empty_state
          else
            steps
          end
        end
      end

      private

      # A strip of stat pills across the full lifecycle (in order), each showing
      # how many boxes sit in that state — the at-a-glance progression.

      #: () -> untyped
      def distribution
        section(
          aria_label: I18n.t("box_steps.show.distribution"),
          class: "flex flex-col gap-stack-gap"
        ) do
          h3(class: "text-label-caps uppercase text-muted") { I18n.t("box_steps.show.distribution") }
          div(class: "grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5") do
            Box::STATUSES.each { |status| state_pill(status) }
          end
        end
      end

      #: (untyped status) -> untyped
      def state_pill(status)
        count = @counts.fetch(status, 0)
        render Components::Ui::Card.new(padding: "p-4") do
          p(class: "text-headline-xl text-text-warm") { count }
          p(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.status.#{status}") }
        end
      end

      #: () -> untyped
      def steps
        section(aria_label: I18n.t("box_steps.show.title"), class: "flex flex-col gap-gutter") do
          @steps.each { |step| step_card(step) }
        end
      end

      #: (untyped step) -> untyped
      def step_card(step)
        count = @counts.fetch(step[:from], 0)
        render Components::Ui::Card.new(padding: "p-6") do
          div(class: "flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between") do
            div(class: "flex flex-col gap-1") do
              h3(class: "text-headline-md text-text-warm") do
                I18n.t("box_steps.show.steps.#{step[:to]}.button", count: count)
              end
              p(class: "text-sm text-on-surface-variant") do
                I18n.t("box_steps.show.steps.#{step[:to]}.caption")
              end
            end
            step_button(step, count)
          end
        end
      end

      # POST to box_steps#create carrying the destination status, behind a native
      # turbo confirm (agent-browser won't auto-accept it — patch window.confirm in
      # live verification). The unpacked step's confirm warns about item removal.

      #: (untyped step, untyped count) -> untyped
      def step_button(step, count)
        button_to(
          I18n.t("box_steps.show.steps.#{step[:to]}.button", count: count),
          move_box_steps_path(@move),
          method: :post,
          params: { to: step[:to] },
          data: { turbo_confirm: I18n.t("box_steps.show.steps.#{step[:to]}.confirm") },
          class: "inline-flex shrink-0 items-center justify-center gap-2 rounded-full " \
                 "bg-accent-sage px-6 py-3 text-sm font-bold text-page transition " \
                 "hover:opacity-90 active:scale-[0.98]"
        )
      end

      #: () -> untyped
      def empty_state
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Boxes,
          title: I18n.t("box_steps.show.empty_title"),
          description: I18n.t("box_steps.show.empty_body")
        )
      end
    end
  end
end
