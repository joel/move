require "rails_helper"

RSpec.describe RecognitionRuns::Reannounce do
  let(:move) { create(:move) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }

  it "re-emits recognition_run.succeeded for a succeeded run" do
    run = create(:recognition_run, :succeeded, move:, box:, media:, metadata: { "item_count" => 3 })
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(run:)

    expect(result).to be_success
    expect(Rails.event).to have_received(:notify)
      .with("recognition_run.succeeded", hash_including(recognition_run_id: run.id, item_count: 3)).once
  end

  it "refuses a run that is not succeeded (nothing to announce)" do
    run = create(:recognition_run, :failed, move:, box:, media:)
    allow(Rails.event).to receive(:notify)

    result = described_class.new.call(run:)

    expect(result).to be_failure
    expect(result.failure).to eq(:not_succeeded)
    expect(Rails.event).not_to have_received(:notify)
  end

  it "degrades a dispatch failure to a warning — never raises over a done run (§1#4)" do
    run = create(:recognition_run, :succeeded, move:, box:, media:, metadata: { "item_count" => 3 })
    allow(Rails.event).to receive(:notify).and_raise(StandardError, "boom")
    allow(Rails.logger).to receive(:warn)

    expect { described_class.new.call(run:) }.not_to raise_error
    expect(Rails.logger).to have_received(:warn).with(/re-announce failed/)
  end
end
