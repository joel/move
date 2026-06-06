require "rails_helper"

RSpec.describe RecognitionRuns::Retry do
  let(:move) { create(:move) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }

  it "queues a new run for a failed run" do
    run = create(:recognition_run, :failed, move:, box:, media:)

    expect do
      expect(described_class.new.call(run:)).to be_success
    end.to change(box.recognition_runs, :count).by(1)
  end

  it "refuses to retry a run that is not failed (no duplicate)" do
    run = create(:recognition_run, :succeeded, move:, box:, media:)

    expect do
      result = described_class.new.call(run:)
      expect(result).to be_failure
      expect(result.failure).to eq(:not_retryable)
    end.not_to change(box.recognition_runs, :count)
  end
end
