# frozen_string_literal: true

require "rails_helper"
require "rake"

# Backfill task (#675). Runs against the current (public) schema by stubbing the
# tenant list to it — the per-tenant Apartment::Tenant.switch is exercised by
# the iteration, switching into the schema where the test fixtures live.
RSpec.describe "images:analyze", type: :task do
  # rubocop:disable RSpec/BeforeAfterAll -- one-time rake-task load, not test state
  before(:all) do
    Rake.application = Rake::Application.new
    # rake_require otherwise skips a file already in `$"`, leaving the task undefined.
    Rake.application.rake_require("tasks/images", [Rails.root.join("lib").to_s], [])
    Rake::Task.define_task(:environment)
  end
  # rubocop:enable RSpec/BeforeAfterAll

  let(:task) { Rake::Task["images:analyze"] }

  before do
    task.reenable
    # Iterate only the current schema (no real tenant schemas exist in test).
    allow(Organization).to receive(:pluck).with(:slug).and_return([Apartment::Tenant.current])
  end

  it "analyzes blobs missing dimensions and skips already-analyzed ones" do
    media = create(:media)
    blob = media.image.blob
    # Simulate a pre-#675 blob: strip the analysis metadata.
    blob.update!(metadata: {})
    expect(blob.reload).not_to be_analyzed

    task.invoke

    blob.reload
    expect(blob.analyzed?).to be(true)
    expect(blob.metadata["width"]).to be_present
    expect(blob.metadata["height"]).to be_present
  end

  it "re-analyzes a blob marked analyzed but missing dimensions (#676 Codex)" do
    media = create(:media)
    blob = media.image.blob
    # An earlier analyzer failure leaves analyzed: true with no dimensions.
    blob.update!(metadata: { "analyzed" => true })

    task.invoke

    blob.reload
    expect(blob.metadata["width"]).to be_present
    expect(blob.metadata["height"]).to be_present
  end

  it "leaves analyzed blobs untouched (idempotent re-run)" do
    media = create(:media)
    blob = media.image.blob
    blob.analyze unless blob.analyzed?
    expect(blob.reload.analyzed?).to be(true)

    expect { task.invoke }.not_to(change { blob.reload.metadata })
  end
end
