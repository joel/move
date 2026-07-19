# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsuranceDossierRuns::RecordProgress do
  let(:move) { create(:move) }

  it "sets the absolute completed count on an active run" do
    run = create(:insurance_dossier_run, :processing, move:, total_count: 10, completed_count: 0)

    described_class.new.call(run_id: run.id, completed: 7)

    expect(run.reload.completed_count).to eq(7)
  end

  it "is a no-op on a finished run (a late call after completion)" do
    run = create(:insurance_dossier_run, :completed, move:, total_count: 5)

    described_class.new.call(run_id: run.id, completed: 99)

    expect(run.reload.completed_count).to eq(5) # unchanged
  end

  it "is a no-op for a blank run id" do
    expect { described_class.new.call(run_id: nil, completed: 1) }.not_to raise_error
  end
end
