# frozen_string_literal: true

module Components
  # A1 Move list item: status badge, name, a progress hint, box count and
  # pending-review count. Box metrics arrive in D2; they render as zero for now.
  # Archived moves render visibly muted (read-only treatment).
  class MoveCard < Components::Base
    include Phlex::Rails::Helpers::ButtonTo

    STATUS_TINT = {
      "planned" => "bg-surface-container-high text-on-surface-variant",
      "started" => "bg-accent-sage/20 text-accent-sage",
      "finished" => "bg-secondary/20 text-secondary",
      "archived" => "bg-surface-container-high text-muted"
    }.freeze

    def initialize(move:)
      @move = move
    end

    def view_template
      # button_to renders a <form>, which is invalid inside an <a> — so the card
      # link and the "Remove sample" control are siblings in a wrapper.
      div(class: "flex flex-col gap-2") do
        a(href: move_boxes_path(@move), class: card_classes) do
          div(class: "flex items-start justify-between gap-3") do
            div do
              div(class: "flex items-center gap-2") do
                span(class: status_classes) { status_label }
                sample_badge if @move.sample?
              end
              h2(class: "mt-1 text-headline-md text-text-warm") { @move.name }
            end
            archived_lock if @move.archived?
          end

          progress_bar
          metrics
        end
        remove_sample_control if @move.sample?
      end
    end

    private

    def sample_badge
      span(class: "inline-flex items-center rounded-full bg-secondary/20 px-2.5 py-0.5 " \
                  "text-label-caps uppercase text-secondary") do
        I18n.t("moves.sample.badge")
      end
    end

    def remove_sample_control
      div(class: "flex justify-end") do
        button_to(
          move_path(@move),
          method: :delete,
          class: "text-label-sm text-error underline underline-offset-2 hover:opacity-80",
          data: { turbo_confirm: I18n.t("moves.sample.remove_confirm") }
        ) { I18n.t("moves.sample.remove") }
      end
    end

    def card_classes
      base = "flex flex-col gap-4 rounded-card border border-card-border bg-card p-5 " \
             "transition hover:-translate-y-0.5 hover:bg-surface-container-high"
      @move.archived? ? "#{base} opacity-60" : base
    end

    def status_classes
      tint = STATUS_TINT.fetch(@move.status, STATUS_TINT["planned"])
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-label-caps uppercase #{tint}"
    end

    def status_label
      I18n.t("moves.status.#{@move.status}", default: @move.status.titleize)
    end

    def archived_lock
      span(class: "text-muted", title: I18n.t("moves.read_only")) { "🔒" }
    end

    def progress_bar
      div(class: "h-2 w-full overflow-hidden rounded-full bg-surface-container-high") do
        div(class: "h-full rounded-full bg-accent-sage", style: "width: 0%")
      end
    end

    def metrics
      div(class: "flex items-center justify-between text-body-md text-on-surface-variant") do
        span(class: "text-text-warm") { I18n.t("moves.packed_hint", packed: 0, total: 0) }
        span { I18n.t("moves.pending_review", count: 0) }
      end
    end
  end
end
