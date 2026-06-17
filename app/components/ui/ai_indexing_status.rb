# frozen_string_literal: true

module Components
  module Ui
    # Live search-indexing status for the AI settings panel (#239). Purely
    # presentational and authorization-independent — it reads only an IndexingRun's
    # counts — so it is safe to broadcast verbatim over Turbo Streams to every
    # subscriber of a Move's indexing stream. The stable DOM id is the broadcast
    # replace target.
    #
    #   render Components::Ui::AiIndexingStatus.new(run: move.indexing_runs.order(:created_at).last)
    class AiIndexingStatus < Components::Base
      ID = "ai-indexing-status"

      def initialize(run:)
        @run = run
      end

      def view_template
        div(id: ID, class: "flex flex-col gap-2") do
          if @run&.in_progress?
            progress
          elsif @run&.status == "completed"
            up_to_date
          end
        end
      end

      private

      def progress
        render Components::Ui::ProgressBar.new(
          value: @run.finished_items, max: @run.total_count, label: t("progress_label")
        )
        span(class: "text-body-md text-on-surface-variant") do
          t("in_progress", done: @run.finished_items, total: @run.total_count)
        end
        span(class: "text-body-sm text-muted") { t("locked_note") }
      end

      def up_to_date
        span(class: "inline-flex items-center gap-1.5 text-label-caps uppercase text-accent-sage") do
          render Components::Icons::Check.new(css: "h-4 w-4")
          plain t("up_to_date")
        end
      end

      def t(key, **)
        I18n.t("settings.show.recognition.embeddings.indexing.#{key}", **)
      end
    end
  end
end
