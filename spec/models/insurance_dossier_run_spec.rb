# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsuranceDossierRun do
  let(:move) { create(:move) }

  it "has a valid factory" do
    expect(build(:insurance_dossier_run, move:)).to be_valid
  end

  describe "status predicates" do
    it "is in_progress while queued/processing" do
      expect(build(:insurance_dossier_run, status: "queued")).to be_in_progress
      expect(build(:insurance_dossier_run, :processing)).to be_in_progress
    end

    it "is ready only when completed AND a document is attached" do
      expect(create(:insurance_dossier_run, :completed, move:)).to be_ready
      run = create(:insurance_dossier_run, move:, status: "completed")
      expect(run).not_to be_ready
    end

    it "is failed when the job aborted" do
      expect(build(:insurance_dossier_run, :failed)).to be_failed
    end
  end
end
