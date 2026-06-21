# frozen_string_literal: true

module Views
  module LabelPrints
    # E1 — Label Print range picker. Choose a box-number range and generate all
    # those exterior labels in one PDF (2 pages per box). POSTs a run: a valid range
    # starts a background generation job and redirects to the live progress page
    # (#303); an invalid/empty range re-renders here with the error (validation
    # stays on this page).
    class Show < Views::Base
      include Phlex::Rails::Helpers::Routes
      include Phlex::Rails::Helpers::FormWith

      def initialize(move:, min_number:, max_number:, box_count:, from: nil, to: nil, error: nil)
        @move = move
        @min_number = min_number
        @max_number = max_number
        @box_count = box_count
        @from = from
        @to = to
        @error = error
      end

      def view_template
        div(class: "flex flex-col gap-section-gap") do
          render Components::Ui::SectionHeader.new(
            eyebrow: @move.name,
            title: I18n.t("label_print.title"),
            subtitle: I18n.t("label_print.subtitle")
          )
          @box_count.zero? ? empty_state : form_card
        end
      end

      private

      def empty_state
        div(class: "ha-card p-8 text-center") do
          p(class: "text-body-md text-muted") { I18n.t("label_print.empty_state") }
        end
      end

      def form_card
        div(class: "ha-card p-6 flex flex-col gap-stack-gap") do
          p(class: "text-body-md text-muted") do
            I18n.t("label_print.range_hint", min: @min_number, max: @max_number, count: @box_count)
          end
          # POSTs a run: the response is an HTML redirect to the progress page, so
          # no data-turbo=false workaround is needed (form_with injects the CSRF
          # token + method). The number fields submit by their `name`.
          form_with(
            url: move_label_print_runs_path(@move), method: :post,
            class: "flex flex-col gap-stack-gap"
          ) do
            div(class: "grid grid-cols-2 gap-3") do
              number_field("from", I18n.t("label_print.from"), @from || @min_number)
              number_field("to", I18n.t("label_print.to"), @to || @max_number)
            end
            render_error
            render Components::Ui::Button.new(
              label: I18n.t("label_print.submit"), type: "submit",
              variant: :primary, full_width: true
            )
          end
        end
      end

      def number_field(name, label, value)
        render Components::Ui::Field.new(
          name: name, label: label, type: "number", value: value,
          required: true, min: 1, inputmode: "numeric"
        )
      end

      def render_error
        return unless @error

        p(class: "text-body-md text-error", role: "alert") { @error }
      end
    end
  end
end
