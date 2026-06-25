# frozen_string_literal: true

require "rails_helper"
require "rake"

# Backfill task (#316). Runs against the current (public) schema by stubbing the
# tenant list to it — the per-tenant Apartment::Tenant.switch is exercised by the
# iteration, switching into the schema where the test fixtures live.
RSpec.describe "images:prewarm", type: :task do
  # rubocop:disable RSpec/BeforeAfterAll -- one-time rake-task load, not test state
  before(:all) do
    Rake.application = Rake::Application.new
    # Pass an empty `loaded` list (not the default `$"`) so the rakefile is
    # (re)loaded into THIS fresh Rake application even when another task spec
    # (images_optimize_spec) already required "tasks/images" earlier in the run —
    # rake_require otherwise skips a file already in `$"`, leaving the task undefined.
    Rake.application.rake_require("tasks/images", [Rails.root.join("lib").to_s], [])
    Rake::Task.define_task(:environment)
  end
  # rubocop:enable RSpec/BeforeAfterAll

  let(:task) { Rake::Task["images:prewarm"] }

  before do
    task.reenable
    # Iterate only the current schema (no real tenant schemas exist in test).
    allow(Organization).to receive(:pluck).with(:slug).and_return([Apartment::Tenant.current])
  end

  it "warms the display variants for existing media" do
    create(:media)

    expect { task.invoke }
      .to change(ActiveStorage::VariantRecord, :count).by(MediaVariants::Prewarm::VARIANTS.size)
  end

  it "is idempotent — a second run re-creates no variant records" do
    create(:media)
    task.invoke

    task.reenable
    expect { task.invoke }.not_to change(ActiveStorage::VariantRecord, :count)
  end

  it "skips discarded media (never displayed, so not worth warming)" do
    create(:media).discard

    expect { task.invoke }.not_to change(ActiveStorage::VariantRecord, :count)
  end
end
