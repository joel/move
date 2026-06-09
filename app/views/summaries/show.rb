# frozen_string_literal: true

module Views
  module Summaries
    # F2 — Volume & weight summary. A page header with a Metric/Imperial unit
    # toggle, an honest "incomplete data" banner, a three-metric bento (total
    # volume / estimated weight / box count), and a per-room breakdown with a
    # volume micro-bar. Built against the Stitch "Summary & Volume (Dark) -
    # Responsive" screen, rendered from project tokens (Stitch is dark-only).
    # All numbers are display conversions of canonical metric storage — switching
    # the unit toggle never changes a stored value.
    class Show < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(move:, summary:)
        @move = move
        @summary = summary
        @measurements = MoveMeasurements.new(unit_system: move.unit_system)
      end

      def view_template
        div(class: "flex flex-col gap-section-gap") do
          header
          if @summary.box_count.zero?
            empty_state
          else
            missing_banner if @summary.missing_dimension_count.positive?
            metric_cards
            room_breakdown
          end
        end
      end

      private

      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: @move.name,
          title: I18n.t("summaries.show.title"),
          subtitle: I18n.t("summaries.show.subtitle")
        ) do
          unit_toggle unless @move.archived?
        end
      end

      # Segmented pill: the active system is an inert label, the other a tiny
      # form that PATCHes Move#unit_system. Hidden entirely on archived Moves.
      def unit_toggle
        div(class: "inline-flex self-start rounded-full border border-card-border bg-card p-1") do
          Move::UNIT_SYSTEMS.each { |system| unit_toggle_option(system) }
        end
      end

      def unit_toggle_option(system)
        label = I18n.t("summaries.show.#{system}")
        if @move.unit_system == system
          span(class: "#{toggle_classes} bg-surface-container-high text-text-warm", aria_current: "true") { label }
        else
          button_to(
            move_summary_unit_system_path(@move),
            method: :patch,
            params: { move: { unit_system: system } },
            class: "#{toggle_classes} text-on-surface-variant hover:text-text-warm"
          ) { label }
        end
      end

      def toggle_classes
        "rounded-full px-6 py-2 text-sm font-semibold transition"
      end

      # Only shown when some box is missing a dimension; "Review" deep-links to
      # Boxes where the dimensions can be filled in.
      def missing_banner
        div(class: "flex flex-col gap-4 rounded-card border border-secondary/40 bg-secondary/10 " \
                   "p-4 sm:flex-row sm:items-center") do
          span(class: "shrink-0 pt-0.5 text-secondary") { render Components::Icons::Alert.new(css: "h-6 w-6") }
          div(class: "flex-1") do
            h3(class: "text-body-md font-semibold text-text-warm") do
              I18n.t("summaries.show.missing_warning_title")
            end
            p(class: "text-sm text-on-surface-variant") do
              I18n.t("summaries.show.missing_warning_body", count: @summary.missing_dimension_count)
            end
          end
          render Components::Ui::Button.new(
            label: I18n.t("summaries.show.review"),
            variant: :secondary,
            href: move_boxes_path(@move)
          )
        end
      end

      def metric_cards
        section(
          aria_label: I18n.t("summaries.show.metrics_label"),
          class: "grid grid-cols-1 gap-gutter md:grid-cols-3"
        ) do
          volume_card
          weight_card
          boxes_card
        end
      end

      def volume_card
        metric_card(
          icon: Components::Icons::Chart,
          label: I18n.t("summaries.show.total_volume"),
          quantity: @measurements.volume(@summary.total_volume_cm3),
          caption: I18n.t("summaries.show.volume_caption"),
          empty: I18n.t("summaries.show.no_volume")
        )
      end

      def weight_card
        metric_card(
          icon: Components::Icons::Boxes,
          label: I18n.t("summaries.show.est_weight"),
          quantity: @measurements.weight(@summary.total_weight_kg),
          caption: I18n.t("summaries.show.weight_caption"),
          empty: I18n.t("summaries.show.no_weight")
        )
      end

      # The box count is always an exact integer (no unit, no "missing" case), so
      # it gets its own emphasised card rather than the Quantity treatment.
      def boxes_card
        render Components::Ui::Card.new(padding: "p-6") do
          metric_head(Components::Icons::Boxes, I18n.t("summaries.show.total_boxes"))
          div do
            p(class: "text-headline-xl text-text-warm") { @summary.box_count }
            p(class: "text-sm text-on-surface-variant") do
              I18n.t("summaries.show.across_rooms", count: room_count)
            end
          end
        end
      end

      def metric_card(icon:, label:, quantity:, caption:, empty:)
        render Components::Ui::Card.new(padding: "p-6") do
          metric_head(icon, label)
          div do
            if quantity
              p(class: "flex items-baseline gap-1") do
                span(class: "text-headline-xl text-text-warm") { quantity.value }
                span(class: "text-body-lg text-on-surface-variant") { quantity.unit }
              end
              p(class: "text-sm text-on-surface-variant") { caption }
            else
              p(class: "text-headline-xl text-on-surface-variant") { "—" }
              p(class: "text-sm text-on-surface-variant") { empty }
            end
          end
        end
      end

      def metric_head(icon, label)
        div(class: "flex items-start justify-between") do
          span(
            class: "flex h-9 w-9 items-center justify-center rounded-full " \
                   "bg-surface-container-high text-accent-sage"
          ) { render icon.new(css: "h-5 w-5") }
          span(class: "text-label-caps uppercase text-muted") { label }
        end
      end

      def room_breakdown
        max_volume = @summary.rooms.filter_map(&:volume_cm3).max
        section(aria_label: I18n.t("summaries.show.room_breakdown"), class: "flex flex-col gap-stack-gap") do
          h3(class: "text-headline-md text-text-warm") { I18n.t("summaries.show.room_breakdown") }
          div(class: "grid grid-cols-1 gap-gutter md:grid-cols-2") do
            @summary.rooms.each { |room_summary| room_card(room_summary, max_volume) }
          end
        end
      end

      def room_card(room_summary, max_volume)
        render Components::Ui::Card.new(padding: "p-5") do
          div(class: "flex items-center justify-between gap-3") do
            div(class: "flex min-w-0 items-center gap-3") do
              span(
                class: "flex h-10 w-10 shrink-0 items-center justify-center rounded-full " \
                       "bg-surface-container-high text-accent-sage"
              ) { render Components::Icons::Boxes.new(css: "h-5 w-5") }
              h4(class: "truncate text-body-md text-text-warm") { room_name(room_summary) }
            end
            div(class: "shrink-0 text-right") do
              p(class: "font-semibold text-text-warm") { room_volume_label(room_summary) }
              p(class: "text-sm text-on-surface-variant") do
                I18n.t("summaries.show.box_count", count: room_summary.box_count)
              end
            end
          end
          render Components::Ui::ProgressBar.new(
            value: room_summary.volume_cm3 || 0,
            max: max_volume || 1
          )
          if room_summary.missing_dimension_count.positive?
            p(class: "text-sm text-secondary") do
              I18n.t("summaries.show.room_missing", count: room_summary.missing_dimension_count)
            end
          end
        end
      end

      def empty_state
        render Components::Ui::Card.new(padding: "p-10") do
          div(class: "flex flex-col items-center gap-4 text-center") do
            span(
              class: "flex h-14 w-14 items-center justify-center rounded-full " \
                     "bg-surface-container-high text-accent-sage"
            ) { render Components::Icons::Chart.new(css: "h-7 w-7") }
            h3(class: "text-headline-md text-text-warm") { I18n.t("summaries.show.empty_title") }
            p(class: "max-w-sm text-body-md text-on-surface-variant") do
              I18n.t("summaries.show.empty_body")
            end
            render Components::Ui::Button.new(
              label: I18n.t("summaries.show.empty_cta"),
              href: move_boxes_path(@move)
            )
          end
        end
      end

      def room_name(room_summary)
        room_summary.room ? room_summary.room.name : I18n.t("summaries.show.unassigned")
      end

      def room_volume_label(room_summary)
        quantity = @measurements.volume(room_summary.volume_cm3)
        quantity ? "#{quantity.value} #{quantity.unit}" : I18n.t("summaries.show.unknown_volume")
      end

      def room_count
        @summary.rooms.count(&:room)
      end
    end
  end
end
