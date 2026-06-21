# frozen_string_literal: true

module Components
  module Ui
    # Live status for a bulk label-print run (#303), mirroring AiIndexingStatus.
    # Purely presentational and authorization-independent — it reads only a
    # LabelPrintRun's counts/status/document — so it is safe to broadcast verbatim
    # over Turbo Streams to every subscriber of the run's progress stream. The
    # stable DOM id is the broadcast replace target.
    #
    #   render Components::Ui::LabelPrintStatus.new(run: run)
    class LabelPrintStatus < Components::Base
      include Phlex::Rails::Helpers::Routes

      ID = "label-print-status"

      def initialize(run:)
        @run = run
      end

      def view_template
        div(id: ID, class: "flex flex-col gap-3") do
          if @run.in_progress?
            progress
          elsif @run.ready?
            ready
          elsif @run.failed?
            failed
          end
        end
      end

      private

      def progress
        render Components::Ui::ProgressBar.new(
          value: @run.completed_count, max: @run.total_count, label: t("progress_label")
        )
        span(class: "text-body-md text-on-surface-variant") do
          t("in_progress", done: @run.completed_count, total: @run.total_count)
        end
      end

      def ready
        span(class: "inline-flex items-center gap-1.5 text-label-caps uppercase text-accent-sage") do
          render Components::Icons::Check.new(css: "h-4 w-4")
          plain t("ready_title")
        end
        render Components::Ui::Button.new(
          label: t("download"), href: download_move_label_print_run_path(@run.move, @run)
        )
      end

      def failed
        span(class: "text-body-md text-secondary") { t("failed_title") }
        render Components::Ui::Button.new(
          label: t("retry"), variant: :secondary, href: move_label_print_path(@run.move)
        )
      end

      def t(key, **)
        I18n.t("label_print.status.#{key}", **)
      end
    end
  end
end
