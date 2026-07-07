# frozen_string_literal: true

require "rails_helper"

# #545 — the domain finalization of async ingest, extracted from IngestJob so
# the media.captured event stays in the action layer. Recognition enqueue is
# stubbed so this stays a fast unit spec (no libvips / no provider call); the
# end-to-end normalize→recognize path is covered (CI-only) by the job spec.
RSpec.describe Captures::CompleteIngest do
  let(:move) { create(:move) }
  let(:box) { create(:box, move:, status: "packing") }
  let(:media) { create(:media, :pending, box:, move:) }
  let(:normalized) do
    { io: Rails.root.join("spec/fixtures/files/sample_image.png").open, filename: "master.jpg" }
  end

  before do
    allow(RecognitionRuns::Enqueue).to receive(:new)
      .and_return(instance_double(RecognitionRuns::Enqueue, call: Dry::Monads::Success()))
  end

  it "attaches the master, flips the pending media to ready, and enqueues recognition" do
    result = described_class.new.call(media:, normalized:, captured_by_id: nil)

    expect(result).to be_success
    media.reload
    expect(media).to be_ready
    expect(media.image).to be_attached
    expect(media.optimized_at).to be_present
    expect(RecognitionRuns::Enqueue).to have_received(:new)
  end
end
