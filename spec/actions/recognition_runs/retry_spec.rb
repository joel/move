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

  it "refuses while a newer run on the photo is already in flight (#896)" do
    run = create(:recognition_run, :failed, move:, box:, media:)
    create(:recognition_run, move:, box:, media:, status: "queued")

    expect do
      expect(described_class.new.call(run:).failure).to eq(:not_retryable)
    end.not_to change(box.recognition_runs, :count)
  end

  it "re-checks under the photo lock, refusing a retry whose pre-check went stale (#896)" do
    run = create(:recognition_run, :failed, move:, box:, media:)
    action = described_class.new
    raced = false
    # A concurrent retry's run commits between this retry's pre-check and its
    # photo lock: the under-lock re-check must see it.
    allow(action).to receive(:retryable?).and_wrap_original do |original, *args|
      original.call(*args).tap do
        create(:recognition_run, move:, box:, media:, status: "queued") unless raced
        raced = true
      end
    end

    expect do
      expect(action.call(run:).failure).to eq(:not_retryable)
    end.to change(box.recognition_runs, :count).by(1) # only the racing run
  end

  it "refuses a failed run that is no longer the photo's latest (#902)" do
    run = create(:recognition_run, :failed, move:, box:, media:, created_at: 1.hour.ago)
    create(:recognition_run, :succeeded, move:, box:, media:) # nothing detected: no items

    expect do
      expect(described_class.new.call(run:).failure).to eq(:not_retryable)
    end.not_to change(box.recognition_runs, :count)
  end

  # A provider whose scan succeeds with nothing on the photo.
  def detecting_nothing
    instance_double(RecognitionProviders::Fake).tap do |provider|
      allow(provider).to receive(:identify)
        .and_return(RecognitionProviders::Result.new(provider: "fake", provider_model: "x", objects: []))
    end
  end

  it "refuses a stale retry once the first retry's run succeeded with nothing detected (#902)" do
    run = create(:recognition_run, :failed, move:, box:, media:, created_at: 1.hour.ago)
    allow(RecognitionRuns::ProcessJob).to receive(:perform_later).and_return(instance_double(RecognitionRuns::ProcessJob))
    stale = described_class.new
    raced = false
    # Retry A runs, and its run is processed to an empty success, between
    # retry B's pre-check and B's photo lock.
    allow(stale).to receive(:retryable?).and_wrap_original do |original, *args|
      original.call(*args).tap do
        next if raced

        raced = true
        first = described_class.new.call(run: RecognitionRun.find(run.id)).value!
        expect(RecognitionRuns::Process.new.call(run: first, provider: detecting_nothing)).to be_success
        expect(first.reload.status).to eq("succeeded")
      end
    end

    expect do
      expect(stale.call(run:).failure).to eq(:not_retryable)
    end.to change(box.recognition_runs, :count).by(1) # only retry A's run
    expect(RecognitionRuns::ProcessJob).to have_received(:perform_later).once
  end

  describe "a retake re-scan run (#897)" do
    before do
      # Items from the earlier image, then the retake swaps the image.
      create(:item, move:, box:, source_media: media, name: "Coffee maker", created_at: 1.hour.ago)
      media.image.attach(io: Rails.root.join("spec/fixtures/files/sample_image.png").open,
                         filename: "retake.png", content_type: "image/png")
    end

    it "is retryable although the photo holds items from an earlier image, and the new run is a re-scan" do
      run = create(:recognition_run, :failed, move:, box:, media:, rescan: true)

      result = described_class.new.call(run:)

      expect(result).to be_success
      expect(result.value!.rescan).to be(true)
    end

    it "is refused once the current image has its own items" do
      run = create(:recognition_run, :failed, move:, box:, media:, rescan: true)
      create(:item, move:, box:, source_media: media, name: "Kettle")

      expect(described_class.new.call(run:).failure).to eq(:not_retryable)
    end

    it "still refuses a plain (non-re-scan) run on the same photo" do
      run = create(:recognition_run, :failed, move:, box:, media:)

      expect(described_class.new.call(run:).failure).to eq(:not_retryable)
    end
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
