# frozen_string_literal: true

require "rails_helper"

RSpec.describe IndexingRun do
  describe "validations" do
    it "is valid with a provider and status" do
      expect(build(:indexing_run)).to be_valid
    end

    it "requires a provider" do
      expect(build(:indexing_run, provider: nil)).not_to be_valid
    end

    it "rejects unknown statuses" do
      expect(build(:indexing_run, status: "halfway")).not_to be_valid
    end
  end

  describe "#in_progress?" do
    it "is true for queued/processing and false for terminal states" do
      expect(build(:indexing_run, status: "queued")).to be_in_progress
      expect(build(:indexing_run, status: "processing")).to be_in_progress
      expect(build(:indexing_run, status: "completed")).not_to be_in_progress
      expect(build(:indexing_run, status: "superseded")).not_to be_in_progress
    end
  end

  describe "#progress_percent" do
    it "is the rounded share of finished (completed + failed) items" do
      run = build(:indexing_run, total_count: 8, completed_count: 1, failed_count: 1)
      expect(run.progress_percent).to eq(25)
    end

    it "is 100 for a zero-item run (nothing to embed)" do
      expect(build(:indexing_run, total_count: 0).progress_percent).to eq(100)
    end

    it "clamps to 100 even if counts overshoot" do
      run = build(:indexing_run, total_count: 2, completed_count: 3)
      expect(run.progress_percent).to eq(100)
    end
  end

  describe ".active scope" do
    it "returns only queued/processing runs" do
      create(:indexing_run, status: "queued")
      create(:indexing_run, :processing)
      create(:indexing_run, :completed)
      create(:indexing_run, :superseded)

      expect(described_class.active.count).to eq(2)
    end
  end
end
