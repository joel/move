# frozen_string_literal: true

require "rails_helper"
require "rake"

# Backfill task (#681). Runs against the current (public) schema by stubbing the
# tenant list to it — the per-tenant Apartment::Tenant.switch is exercised by
# the iteration, switching into the schema where the test fixtures live.
RSpec.describe "images:lqip", type: :task do
  # rubocop:disable RSpec/BeforeAfterAll -- one-time rake-task load, not test state
  before(:all) do
    Rake.application = Rake::Application.new
    # rake_require otherwise skips a file already in `$"`, leaving the task undefined.
    Rake.application.rake_require("tasks/images", [Rails.root.join("lib").to_s], [])
    Rake::Task.define_task(:environment)
  end
  # rubocop:enable RSpec/BeforeAfterAll

  let(:task) { Rake::Task["images:lqip"] }

  before do
    task.reenable
    # Iterate only the current schema (no real tenant schemas exist in test).
    allow(Organization).to receive(:pluck).with(:slug).and_return([Apartment::Tenant.current])
  end

  it "stores a blur-up preview for blobs missing one" do
    media = create(:media)
    blob = media.image.blob
    expect(blob.metadata["lqip"]).to be_nil

    task.invoke

    lqip = blob.reload.metadata["lqip"]
    skip "libvips unavailable" if lqip.nil? && ImageNormalizer.lqip_base64(blob.download).nil?
    expect(lqip).to match(%r{\A[A-Za-z0-9+/]+={0,2}\z})
  end

  it "leaves blobs with an existing preview untouched (idempotent re-run)" do
    media = create(:media)
    blob = media.image.blob
    blob.update!(metadata: blob.metadata.merge("lqip" => "dGVzdA=="))

    expect { task.invoke }.not_to(change { blob.reload.metadata["lqip"] })
  end
end
