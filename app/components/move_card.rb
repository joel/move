# frozen_string_literal: true

module Components
  # A1 Move list item: status badge, name, packed progress, and pending-review
  # count. +metrics+ carries the move's real aggregates (a
  # Moves::CardMetrics::Metrics — #513 replaced the A1 placeholder zeros) and is
  # REQUIRED so a new render site can't silently regress to fake zeros. Archived
  # moves render visibly muted (read-only treatment).
  class MoveCard < Components::Base
    include Phlex::Rails::Helpers::ButtonTo

    STATUS_TINT = {
      "planned" => "bg-surface-container-high text-on-surface-variant",
      "started" => "bg-accent-sage/20 text-accent-sage",
      "finished" => "bg-secondary/20 text-secondary",
      "archived" => "bg-surface-container-high text-muted"
    }.freeze

    #: (move: untyped, metrics: untyped, ?user: untyped) -> void
    def initialize(move:, metrics:, user: nil)
      @move = move
      @metrics = metrics
      @user = user
    end

    #: () -> void
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
        remove_sample_control if removable?
      end
    end

    private

    # Only an admin of the Move can delete it (MovePolicy#destroy?), so don't render
    # a destructive affordance that a viewer/contributor would only get a 403 from.

    #: () -> untyped
    def removable?
      @move.sample? && @move.membership_for(@user)&.admin?
    end

    #: () -> untyped
    def sample_badge
      span(class: "inline-flex items-center rounded-full bg-secondary/20 px-2.5 py-0.5 " \
                  "text-label-caps uppercase text-secondary") do
        I18n.t("moves.sample.badge")
      end
    end

    #: () -> untyped
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

    #: () -> String
    def card_classes
      base = "flex flex-col gap-4 rounded-card border border-card-border bg-card p-5 " \
             "transition hover:-translate-y-0.5 hover:bg-surface-container-high"
      @move.archived? ? "#{base} opacity-60" : base
    end

    #: () -> String
    def status_classes
      tint = STATUS_TINT.fetch(@move.status, STATUS_TINT["planned"])
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-label-caps uppercase #{tint}"
    end

    #: () -> untyped
    def status_label
      I18n.t("moves.status.#{@move.status}", default: @move.status.titleize)
    end

    #: () -> untyped
    def archived_lock
      span(class: "text-muted", title: I18n.t("moves.read_only")) { "🔒" }
    end

    #: () -> untyped
    def progress_bar
      div(class: "h-2 w-full overflow-hidden rounded-full bg-surface-container-high") do
        div(class: "h-full rounded-full bg-accent-sage", style: "width: #{packed_percent}%")
      end
    end

    #: () -> untyped
    def packed_percent
      return 0 if @metrics.total.zero?

      (@metrics.packed * 100.0 / @metrics.total).round
    end

    #: () -> untyped
    def metrics
      div(class: "flex items-center justify-between text-body-md text-on-surface-variant") do
        span(class: "text-text-warm") do
          I18n.t("moves.packed_hint", packed: @metrics.packed, total: @metrics.total)
        end
        span { I18n.t("moves.pending_review", count: @metrics.pending_review) }
      end
    end
  end
end
