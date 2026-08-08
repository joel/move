# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::Unpack do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:box) { create(:box, move:, status: "unpacking") }

  it "marks the item removed and reports no completion while others remain" do
    item = create(:item, :manual, move:, box:)
    create(:item, :manual, move:, box:)

    result = described_class.new.call(item:, actor:)

    aggregate_failures do
      expect(result.value![:completed_box]).to be_nil
      expect(item.reload.presence_state).to eq("removed")
      expect(box.reload.status).to eq("unpacking")
    end
  end

  it "completes the box when the item was its last (#755)" do
    item = create(:item, :manual, move:, box:)

    result = described_class.new.call(item:, actor:)

    aggregate_failures do
      expect(result.value![:completed_box]).to eq(item.box)
      expect(item.reload.presence_state).to eq("removed")
      expect(box.reload.status).to eq("unpacked")
    end
  end

  it "preserves the committed removal when the completion fails (#756 R4)" do
    item = create(:item, :manual, move:, box:)
    failing = instance_double(Boxes::CompleteIfEmpty)
    allow(Boxes::CompleteIfEmpty).to receive(:new).and_return(failing)
    allow(failing).to receive(:call).and_return(Dry::Monads::Failure(:move_archived))

    result = described_class.new.call(item:, actor:)

    aggregate_failures do
      expect(result).to be_success
      expect(result.value![:completed_box]).to be_nil
      expect(item.reload.presence_state).to eq("removed")
    end
  end

  it "passes MarkRemoved's phase guard through without touching the box" do
    packing = create(:box, move:, status: "packing")
    item = create(:item, :manual, move:, box: packing)

    result = described_class.new.call(item:, actor:)

    expect(result).to eq(Dry::Monads::Failure(:wrong_phase))
    expect(packing.reload.status).to eq("packing")
  end
end
