# frozen_string_literal: true

module Views
  module LabelPrints
    # E1 — Label Print range picker. Choose a box-number range and print all those
    # exterior labels in one PDF (2 pages per box). A plain GET form to the print
    # action: a valid range navigates to the inline PDF; an invalid/empty range
    # re-renders here with the error (so validation stays on this page).
    class Show < Views::Base
      include Phlex::Rails::Helpers::Routes

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
          # data-turbo=false: a valid range returns application/pdf (not HTML), and
          # Turbo Drive can't turn a non-HTML form response into a navigation — the
          # button would appear to do nothing. Force a native submit so the browser
          # renders/downloads the PDF. ("false" as a string — Phlex omits
          # boolean-false attributes.)
          form(
            action: move_label_print_labels_path(@move), method: "get",
            data: { turbo: "false" }, class: "flex flex-col gap-stack-gap"
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
