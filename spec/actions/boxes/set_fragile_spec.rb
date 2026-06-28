require "rails_helper"

RSpec.describe Boxes::SetFragile do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

  def set_fragile(box, fragile)
    described_class.new.call(box:, fragile:, actor:)
  end

  it "marks a box fragile" do
    box = create(:box, move:, fragile: false)

    expect(set_fragile(box, true)).to be_success
    expect(box.reload.fragile?).to be(true)
  end

  it "removes the fragile mark" do
    box = create(:box, move:, fragile: true)

    expect(set_fragile(box, false)).to be_success
    expect(box.reload.fragile?).to be(false)
  end

  it "coerces a string flag from the form (\"1\"/\"0\")" do
    box = create(:box, move:, fragile: false)

    set_fragile(box, "1")
    expect(box.reload.fragile?).to be(true)

    set_fragile(box, "0")
    expect(box.reload.fragile?).to be(false)
  end

  it "emits box.set_fragile with the new state" do
    box = create(:box, move:, fragile: false)
    allow(Rails.event).to receive(:notify)

    set_fragile(box, true)

    expect(Rails.event).to have_received(:notify)
      .with("box.set_fragile", hash_including(box_id: box.id, move_id: move.id, fragile: true))
  end

  it "is blocked on an archived (read-only) move" do
    archived = create(:move, :archived, created_by: actor)
    box = create(:box, move: archived, fragile: false)

    result = set_fragile(box, true)

    expect(result).to be_failure
    expect(result.failure).to eq(:move_archived)
    expect(box.reload.fragile?).to be(false)
  end
end
