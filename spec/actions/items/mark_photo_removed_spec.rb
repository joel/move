# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::MarkPhotoRemoved do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:, status: "unpacking") }

  it "marks every still-in-box item sourced from the photo as removed" do
    photo = create(:media, move:, box:)
    plates = create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates")
    mugs = create(:item, :confirmed, move:, box:, source_media: photo, name: "Mugs")
    bowls = create(:item, :confirmed, move:, box:, source_media: photo, name: "Bowls",
                                      presence_state: "removed")
    lamp = create(:item, :confirmed, move:, box:, name: "Lamp")

    result = described_class.new.call(box:, media: photo, actor:)

    expect(result).to be_success
    aggregate_failures do
      expect(plates.reload.presence_state).to eq("removed")
      expect(mugs.reload.presence_state).to eq("removed")
      expect(bowls.reload.presence_state).to eq("removed")
      # An item from another photo (or manual) is untouched.
      expect(lamp.reload.presence_state).to eq("in_box")
    end
  end

  it "does not reach a sibling item moved out to another box" do
    photo = create(:media, move:, box:)
    moved = create(:item, :confirmed, move:, box: create(:box, move:), source_media: photo, name: "Kettle")

    result = described_class.new.call(box:, media: photo, actor:)

    expect(result).to be_success
    expect(moved.reload.presence_state).to eq("in_box")
  end

  it "refuses a photo that belongs to another box, touching nothing (#729)" do
    foreign = create(:media, move:, box: create(:box, move:, status: "unpacking"))
    # An item moved into THIS box keeps its source_media_id — without the
    # ownership guard the box-scoped query would still unpack it.
    stray = create(:item, :confirmed, move:, box:, source_media: foreign, name: "Kettle")
    sibling = create(:item, :confirmed, move:, box: foreign.box, source_media: foreign, name: "Toaster")

    result = described_class.new.call(box:, media: foreign, actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:not_found)
    aggregate_failures do
      expect(stray.reload.presence_state).to eq("in_box")
      expect(sibling.reload.presence_state).to eq("in_box")
      expect(box.reload.status).to eq("unpacking")
    end
  end

  it "skips items a concurrent photo move re-boxed after the load (Codex #876 R1)" do
    photo = create(:media, move:, box:)
    plates = create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates")
    mugs = create(:item, :confirmed, move:, box:, source_media: photo, name: "Mugs")
    create(:item, :confirmed, move:, box:, name: "Lamp") # keeps the box open
    sealed = create(:box, move:, status: "unpacking")
    # The move commits right after the first box-locked section (ownership
    # check + item load) and before the per-item removals — the stale loaded
    # items must not be unpacked in their new box.
    calls = 0
    allow(box).to receive(:with_lock).and_wrap_original do |original, *args, &block|
      result = original.call(*args, &block)
      if (calls += 1) == 1
        [plates, mugs, photo].each { |record| record.update!(box: sealed) }
      end
      result
    end

    result = described_class.new.call(box:, media: photo, actor:)

    expect(result.value![:items]).to be_empty
    expect([plates.reload, mugs.reload].map(&:presence_state)).to all(eq("in_box"))
  end

  it "refuses while the box is not unpacking" do
    packing_box = create(:box, move:, status: "packing")
    photo = create(:media, move:, box: packing_box)
    item = create(:item, :confirmed, move:, box: packing_box, source_media: photo, name: "Vase")

    result = described_class.new.call(box: packing_box, media: photo, actor:)

    expect(result).to be_failure
    expect(result.failure).to eq(:wrong_phase)
    expect(item.reload.presence_state).to eq("in_box")
  end

  it "refuses on an archived move" do
    archived = create(:move, :archived, created_by: actor)
    archived_box = create(:box, move: archived, status: "unpacking")
    photo = create(:media, move: archived, box: archived_box)
    item = create(:item, :confirmed, move: archived, box: archived_box, source_media: photo, name: "Pan")

    result = described_class.new.call(box: archived_box, media: photo, actor:)

    expect(result).to be_failure
    expect(item.reload.presence_state).to eq("in_box")
  end

  it "completes the box when the photo held its last items (#755)" do
    photo = create(:media, move:, box:)
    create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates")

    result = described_class.new.call(box:, media: photo, actor:)

    expect(result.value![:completed_box]).to eq(box)
    expect(box.reload.status).to eq("unpacked")
  end

  it "reports no completion while other items remain" do
    photo = create(:media, move:, box:)
    create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates")
    create(:item, :confirmed, move:, box:, name: "Lamp")

    expect(described_class.new.call(box:, media: photo, actor:).value![:completed_box]).to be_nil
    expect(box.reload.status).to eq("unpacking")
  end

  it "emits one item.removed event per item it removes" do
    photo = create(:media, move:, box:)
    create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates")
    create(:item, :confirmed, move:, box:, source_media: photo, name: "Mugs")
    allow(Rails.event).to receive(:notify)

    described_class.new.call(box:, media: photo, actor:)

    expect(Rails.event).to have_received(:notify)
      .with("item.removed", hash_including(box_id: box.id)).twice
  end
end
