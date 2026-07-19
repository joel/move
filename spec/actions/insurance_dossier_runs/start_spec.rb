# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsuranceDossierRuns::Start do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    allow(InsuranceDossierRuns::GenerateJob).to receive(:perform_later)
    allow(Rails.event).to receive(:notify)
  end

  def box_with_item(number, presence: "in_box")
    box = create(:box, move:, number: number.to_s)
    create(:item, :manual, move:, box:, name: "Thing #{number}", presence_state: presence)
    box
  end

  it "creates a processing run counting items + boxes, emits the audit event, and enqueues the job" do
    # 10 before 2 lexically — the snapshot must order numerically (#283 class).
    boxes = [box_with_item(10), box_with_item(2)]
    create(:box, move:, number: "3") # empty box — not part of the dossier

    result = described_class.new.call(move: move, actor: user)

    expect(result).to be_success
    run = result.value!
    aggregate_failures do
      expect(run.status).to eq("processing")
      expect(run.total_count).to eq(2)
      expect(run.item_count).to eq(2)
      # Snapshot in numeric box order, only boxes holding in_box items.
      expect(InsuranceDossierRuns::GenerateJob).to have_received(:perform_later).with(
        run.id, tenant: Apartment::Tenant.current, box_ids: [boxes[1].id, boxes[0].id]
      )
      expect(Rails.event).to have_received(:notify).with(
        "insurance.dossier_generated",
        move_id: move.id, actor_id: user.id, run_id: run.id, box_count: 2, item_count: 2
      )
    end
  end

  it "fails :empty when the move has no in_box items" do
    box_with_item(1, presence: "removed")

    result = described_class.new.call(move: move, actor: user)

    expect(result).to be_failure
    expect(result.failure).to eq(:empty)
    expect(InsuranceDossierRuns::GenerateJob).not_to have_received(:perform_later)
  end

  it "fails :too_many when the page-budget estimate is exceeded (many one-item boxes, #706)" do
    box_with_item(1)
    stub_const("InsuranceDossierRuns::Start::MAX_PAGES", 0)

    result = described_class.new.call(move: move, actor: user)

    expect(result.failure).to eq(:too_many)
  end

  it "fails :too_many over the item cap without creating a run" do
    box_with_item(1)
    stub_const("InsuranceDossierRuns::Start::MAX_ITEMS", 0)

    result = nil
    expect { result = described_class.new.call(move: move, actor: user) }
      .not_to change(InsuranceDossierRun, :count)
    expect(result.failure).to eq(:too_many)
  end
end
