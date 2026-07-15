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

  it "refuses to retry when the media already yielded kept items (#649)" do
    # A pre-#649 legacy failed run with committed inventory, or a stale tab
    # retrying a media a later run succeeded on — re-running would duplicate.
    run = create(:recognition_run, :failed, move:, box:, media:)
    create(:item, move:, box:, source_media: media, name: "Coffee maker")

    expect do
      result = described_class.new.call(run:)
      expect(result).to be_failure
      expect(result.failure).to eq(:not_retryable)
    end.not_to change(box.recognition_runs, :count)
  end

  it "allows the retry again once the media's items were deleted" do
    run = create(:recognition_run, :failed, move:, box:, media:)
    create(:item, move:, box:, source_media: media, name: "Coffee maker").discard

    expect do
      expect(described_class.new.call(run:)).to be_success
    end.to change(box.recognition_runs, :count).by(1)
  end

  it "refuses to retry on an archived Move, queuing no new run (#118)" do
    archived = create(:move, :archived)
    abox = create(:box, move: archived)
    amedia = create(:media, move: archived, box: abox)
    run = create(:recognition_run, :failed, move: archived, box: abox, media: amedia)

    expect do
      result = described_class.new.call(run:)
      expect(result).to be_failure
      expect(result.failure).to eq(:move_archived)
    end.not_to change(RecognitionRun, :count)
  end
end
