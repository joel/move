# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::RestoreToBox do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:item) { create(:item, :manual, move:, presence_state: "removed") }

  it "flips presence back to in_box (inverse of MarkRemoved)" do
    result = described_class.new.call(item:, actor:)

    expect(result).to be_success
    expect(item.reload.presence_state).to eq("in_box")
  end

  it "refuses to restore into a completed (unpacked) box — reopen first (#756)" do
    box = create(:box, move:, status: "unpacked")
    removed = create(:item, :manual, move:, box:, presence_state: "removed")

    result = described_class.new.call(item: removed, actor:)

    expect(result).to eq(Dry::Monads::Failure(:box_unpacked))
    expect(removed.reload.presence_state).to eq("removed")
  end

  it "re-reads the box under its lock — a stale in-memory status cannot slip past a completion (#756 R2)" do
    box = create(:box, move:, status: "unpacking")
    removed = create(:item, :manual, move:, box:, presence_state: "removed")
    removed.box.status # memoize the association while it still reads `unpacking`
    # A concurrent completion committed behind the memoized object's back
    # (update_all: a raw write is the point — no callbacks, no cache refresh).
    Box.where(id: box.id).update_all(status: "unpacked") # rubocop:disable Rails/SkipsModelValidations

    result = described_class.new.call(item: removed, actor:)

    expect(result).to eq(Dry::Monads::Failure(:box_unpacked))
    expect(removed.reload.presence_state).to eq("removed")
  end

  it "no-ops without a second event when the item is already in its box (replay)" do
    in_box = create(:item, :manual, move:, presence_state: "in_box")

    allow(Rails.event).to receive(:notify)
    result = described_class.new.call(item: in_box, actor:)

    expect(result).to be_success
    expect(Rails.event).not_to have_received(:notify)
  end
end
