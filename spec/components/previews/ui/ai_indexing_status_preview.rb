# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::AiIndexingStatus (#530). The
  # component reads only an IndexingRun's counts/status, so unsaved
  # FactoryBot.build records cover every state without touching the database.
  class AiIndexingStatusPreview < Lookbook::Preview
    def in_progress
      run = FactoryBot.build(:indexing_run, :processing,
                             move: nil, total_count: 12, completed_count: 7)
      render Components::Ui::AiIndexingStatus.new(run: run)
    end

    def in_progress_with_failures
      run = FactoryBot.build(:indexing_run, :processing,
                             move: nil, total_count: 12, completed_count: 6, failed_count: 2)
      render Components::Ui::AiIndexingStatus.new(run: run)
    end

    def up_to_date
      run = FactoryBot.build(:indexing_run, :completed, move: nil, total_count: 12)
      render Components::Ui::AiIndexingStatus.new(run: run)
    end

    # No run yet — renders only the (empty) broadcast target.
    def idle
      render Components::Ui::AiIndexingStatus.new(run: nil)
    end
  end
end
