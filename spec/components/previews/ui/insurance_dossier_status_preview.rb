# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::InsuranceDossierStatus (#702).
  # Unsaved FactoryBot.build records with fixed uuids — the ready/failed states
  # build download/retry links from run.move, so the route params must be
  # present, but nothing is persisted.
  class InsuranceDossierStatusPreview < Lookbook::Preview
    MOVE_ID = "00000000-0000-4000-8000-000000000011"
    RUN_ID = "00000000-0000-4000-8000-000000000012"

    def in_progress
      run = FactoryBot.build(:insurance_dossier_run, :processing, move: nil,
                                                                  total_count: 8, completed_count: 3)
      render Components::Ui::InsuranceDossierStatus.new(run: run)
    end

    # Completed with an attached PDF — shows the download button.
    def ready
      move = FactoryBot.build(:move, id: MOVE_ID)
      run = FactoryBot.build(:insurance_dossier_run, :completed, id: RUN_ID, move: move)
      render Components::Ui::InsuranceDossierStatus.new(run: run)
    end

    def failed
      move = FactoryBot.build(:move, id: MOVE_ID)
      run = FactoryBot.build(:insurance_dossier_run, :failed, id: RUN_ID, move: move)
      render Components::Ui::InsuranceDossierStatus.new(run: run)
    end
  end
end
