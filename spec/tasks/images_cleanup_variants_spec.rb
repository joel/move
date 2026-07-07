# frozen_string_literal: true

require "rails_helper"
require "rake"

# One-off decommission task (#572): purges leftover Active Storage variant records
# and their stored objects after the edge-transform cutover. VariantRecord/Blob are
# Apartment-excluded (shared public schema), so the task runs once against the
# current schema — no per-tenant switch.
RSpec.describe "images:cleanup_variants", type: :task do
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

  let(:task) { Rake::Task["images:cleanup_variants"] }

  before { task.reenable }

  # Build a variant record + its stored object WITHOUT libvips: attach a raw blob
  # straight to a VariantRecord (mirrors what the old Prewarm pipeline left behind),
  # so the purge logic is verifiable on any machine.
  def build_variant_record(media)
    variant_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("variant-bytes"), filename: "thumb.jpg", content_type: "image/jpeg"
    )
    record = ActiveStorage::VariantRecord.create!(blob: media.image.blob, variation_digest: SecureRandom.hex(8))
    record.image.attach(variant_blob)
    record
  end

  it "purges every variant record and its stored object" do
    media = create(:media)
    record = build_variant_record(media)
    variant_blob_id = record.image.blob.id

    expect { task.invoke }.to change(ActiveStorage::VariantRecord, :count).by(-1)

    expect(ActiveStorage::VariantRecord.exists?(record.id)).to be(false)
    expect(ActiveStorage::Blob.exists?(variant_blob_id)).to be(false) # the stored object is gone
  end

  it "is idempotent — a re-run with no variant records left is a no-op" do
    expect { task.invoke }.not_to change(ActiveStorage::VariantRecord, :count)
  end
end
