# frozen_string_literal: true

require "rails_helper"

RSpec.describe InsuranceDossierRuns::GenerateJob do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:tenant) { Apartment::Tenant.current }

  def seed_box(number)
    box = create(:box, :with_room, move:, number: number.to_s)
    create(:item, :manual, move:, box:, name: "Thing #{number}")
    box
  end

  def run_for(box_ids, items)
    create(:insurance_dossier_run, move:, total_count: box_ids.size, item_count: items,
                                   status: "processing")
  end

  it "renders the PDF, attaches it, and completes the run" do
    ids = [seed_box(1), seed_box(2)].map(&:id)
    run = run_for(ids, 2)

    described_class.perform_now(run.id, tenant:, box_ids: ids)

    run.reload
    aggregate_failures do
      expect(run.status).to eq("completed")
      expect(run.completed_count).to eq(2)
      expect(run.document).to be_attached
      expect(run.document.download[0, 4]).to eq("%PDF")
      expect(run.document.content_type).to eq("application/pdf")
    end
  end

  it "renders only the snapshotted ids and still finalizes to the announced total" do
    ids = [seed_box(1), seed_box(2)].map(&:id)
    run = run_for(ids, 2)
    move.boxes.find_by(number: "2").destroy

    described_class.perform_now(run.id, tenant:, box_ids: ids)

    expect(run.reload.status).to eq("completed")
    expect(run.completed_count).to eq(2)
  end

  it "marks the run failed, broadcasts, and re-raises on a render error" do
    ids = [seed_box(1)].map(&:id)
    run = run_for(ids, 1)
    allow(InsuranceDossierPdf).to receive(:new).and_raise(Prawn::Errors::CannotFit)

    expect { described_class.perform_now(run.id, tenant:, box_ids: ids) }
      .to raise_error(Prawn::Errors::CannotFit)
    expect(run.reload.status).to eq("failed")
  end

  it "fails the run when render-time items exceed the cap (items grew while queued)" do
    ids = [seed_box(1)].map(&:id)
    run = run_for(ids, 1)
    stub_const("InsuranceDossierRuns::Start::MAX_ITEMS", 0)

    expect { described_class.perform_now(run.id, tenant:, box_ids: ids) }
      .to raise_error(InsuranceDossierRuns::GenerateJob::TooManyItems)
    expect(run.reload.status).to eq("failed")
  end

  it "no-ops on a run that is already terminal (idempotent retry)" do
    ids = [seed_box(1)].map(&:id)
    run = create(:insurance_dossier_run, :failed, move:)

    expect { described_class.perform_now(run.id, tenant:, box_ids: ids) }
      .not_to(change { run.reload.attributes })
  end
end
