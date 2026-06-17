# frozen_string_literal: true

require "rails_helper"

# Exercises the live wiring (initializer → subscriber → broadcast) by emitting the
# real recognition_run.* events the way RecognitionRuns::Process does (#241).
RSpec.describe Captures::SessionBroadcastSubscriber do
  let(:move) { create(:move) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }
  let(:run) { create(:recognition_run, :processing, move:, box:, media:) }

  def emit(name, **payload)
    Rails.event.notify(name, **payload)
  end

  it "broadcasts the re-rendered session panel to the Box's recognition stream on a run event" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    emit("recognition_run.succeeded", recognition_run_id: run.id, item_count: 0)

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to)
      .with(box, :recognition, hash_including(target: Views::Captures::SessionPanel::ID, html: kind_of(String)))
  end

  it "broadcasts on processing and failed too" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    emit("recognition_run.processing", recognition_run_id: run.id)
    emit("recognition_run.failed", recognition_run_id: run.id, error_code: "X")

    expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).twice
  end

  it "ignores unrelated events" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    emit("item.created", item_id: SecureRandom.uuid, move_id: move.id)

    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
  end

  it "no-ops when the run no longer exists" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)

    emit("recognition_run.succeeded", recognition_run_id: SecureRandom.uuid)

    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
  end
end
