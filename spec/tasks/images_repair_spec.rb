# frozen_string_literal: true

require "rails_helper"
require "rake"

# Repair task (#486). Same tenant-sweep shape as images:prewarm, but heals
# orphaned variants (record row present, file missing) instead of only warming
# missing ones. Runs against the current (public) schema by stubbing the tenant
# list to it.
RSpec.describe "images:repair", type: :task do
  # rubocop:disable RSpec/BeforeAfterAll -- one-time rake-task load, not test state
  before(:all) do
    Rake.application = Rake::Application.new
    # Empty `loaded` list (not the default `$"`) so the rakefile is (re)loaded into
    # THIS fresh Rake application even when another task spec already required
    # "tasks/images" earlier in the run (see images_prewarm_spec).
    Rake.application.rake_require("tasks/images", [Rails.root.join("lib").to_s], [])
    Rake::Task.define_task(:environment)
  end
  # rubocop:enable RSpec/BeforeAfterAll

  let(:task) { Rake::Task["images:repair"] }

  before do
    task.reenable
    allow(Organization).to receive(:pluck).with(:slug).and_return([Apartment::Tenant.current])
  end

  it "rebuilds a variant whose file has gone missing from storage" do
    media = create(:media)
    MediaVariants::Prewarm.call(media) # warm both variants
    master = media.image.blob
    thumb_digest = media.image.variant(:thumb).variation.digest
    orphaned = media.image.variant(:thumb).processed.image.blob
    orphaned.service.delete(orphaned.key) # simulate isolated object-store loss
    expect(orphaned.service.exist?(orphaned.key)).to be(false)

    task.invoke

    # Assert on the persisted record straight from storage — no `.processed`, which
    # would lazily rebuild and mask a repair that destroyed but never regenerated.
    rec = ActiveStorage::VariantRecord.find_by(blob_id: master.id, variation_digest: thumb_digest)
    expect(rec).to be_present
    expect(rec.image.blob.service.exist?(rec.image.blob.key)).to be(true)
  end

  it "warms missing variants for existing media" do
    create(:media)

    expect { task.invoke }
      .to change(ActiveStorage::VariantRecord, :count).by(MediaVariants::Prewarm::VARIANTS.size)
  end

  it "skips discarded media (never displayed, so not worth repairing)" do
    create(:media).discard

    expect { task.invoke }.not_to change(ActiveStorage::VariantRecord, :count)
  end
end
