# frozen_string_literal: true

require "rails_helper"

RSpec.describe LabelPrintRun do
  let(:move) { create(:move) }

  it "has a valid factory" do
    expect(build(:label_print_run, move:)).to be_valid
  end

  describe ".box_cap (#312)" do
    it "is the box cap at the default 2 copies (page cap not binding)" do
      expect(described_class.box_cap(2)).to eq(described_class::MAX_LABELS) # min(200, 400/2)=200
    end

    it "drops to the page cap divided by copies when copies are high" do
      expect(described_class.box_cap(10)).to eq(40) # min(200, 400/10)
      expect(described_class.box_cap(5)).to eq(80)  # min(200, 400/5)
    end

    it "floors a zero/negative copies to 1 so it never divides by zero" do
      expect(described_class.box_cap(0)).to eq(described_class::MAX_LABELS)
    end
  end

  describe "#progress_percent" do
    it "is a clamped whole-number percent of completed/total" do
      run = build(:label_print_run, total_count: 8, completed_count: 2)
      expect(run.progress_percent).to eq(25)
    end

    it "is 100 for a zero-box run (nothing to render)" do
      expect(build(:label_print_run, total_count: 0, completed_count: 0).progress_percent).to eq(100)
    end
  end

  describe "status predicates" do
    it "is in_progress while queued/processing" do
      expect(build(:label_print_run, status: "queued")).to be_in_progress
      expect(build(:label_print_run, :processing)).to be_in_progress
    end

    it "is ready only when completed AND a document is attached" do
      expect(create(:label_print_run, :completed, move:)).to be_ready
      # completed status but no attached document is NOT ready
      run = create(:label_print_run, move:, status: "completed")
      expect(run).not_to be_ready
    end

    it "is failed when the job aborted" do
      expect(build(:label_print_run, :failed)).to be_failed
    end
  end
end
