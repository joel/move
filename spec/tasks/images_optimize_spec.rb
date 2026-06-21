# frozen_string_literal: true

require "rails_helper"
require "rake"

# Backfill task (Phase 42). Runs against the current (public) schema by stubbing
# the tenant list to it — the per-tenant Apartment::Tenant.switch is exercised by
# the iteration, switching into the schema where the test fixtures live.
RSpec.describe "images:optimize", type: :task do
  # rubocop:disable RSpec/BeforeAfterAll -- one-time rake-task load, not test state
  before(:all) do
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/images", [Rails.root.join("lib").to_s])
    Rake::Task.define_task(:environment)
  end
  # rubocop:enable RSpec/BeforeAfterAll

  let(:task) { Rake::Task["images:optimize"] }

  before do
    task.reenable
    # Iterate only the current schema (no real tenant schemas exist in test).
    allow(Organization).to receive(:pluck).with(:slug).and_return([Apartment::Tenant.current])
  end

  def attach_large_jpeg(media)
    require "vips"
    bytes = Vips::Image.gaussnoise(3000, 2000, mean: 128, sigma: 50).cast("uchar").jpegsave_buffer(Q: 92)
    media.image.attach(io: StringIO.new(bytes), filename: "big.jpg", content_type: "image/jpeg")
    bytes.bytesize # create(:media) leaves optimized_at nil, so the backfill picks it up
  rescue LoadError
    skip "libvips unavailable"
  end

  it "downscales an un-optimised blob, stamps tracking columns, and reclaims storage" do
    media = create(:media)
    original = attach_large_jpeg(media)

    task.invoke

    media.reload
    img = Vips::Image.new_from_buffer(media.image.blob.download, "")
    expect([img.width, img.height].max).to eq(ImageNormalizer::MASTER_IMAGE_EDGE)
    expect(media.image.blob.byte_size).to be < original
    expect(media.optimized_at).to be_present
    expect(media.original_byte_size).to eq(original)
  end

  it "is idempotent — a second run skips already-optimised media" do
    media = create(:media)
    attach_large_jpeg(media)

    task.invoke
    optimised_blob_id = media.reload.image.blob.id
    stamped_at = media.optimized_at

    task.reenable
    task.invoke

    media.reload
    expect(media.image.blob.id).to eq(optimised_blob_id) # untouched
    expect(media.optimized_at).to eq(stamped_at)
  end

  it "leaves already-stamped (freshly captured) media untouched" do
    media = create(:media)
    media.update!(optimized_at: 1.hour.ago)
    blob_id = media.image.blob.id

    task.invoke

    expect(media.reload.image.blob.id).to eq(blob_id)
  end

  it "skips a media with an operational storage error and still optimises the rest (#305)" do
    bad = create(:media) # processed first (id asc) — its blob download blows up
    good = create(:media)
    attach_large_jpeg(good)
    calls = 0
    allow(ImageNormalizer).to receive(:call).and_wrap_original do |orig, *args, **kwargs|
      calls += 1
      raise ActiveStorage::FileNotFoundError if calls == 1

      orig.call(*args, **kwargs)
    end

    expect { task.invoke }.not_to raise_error

    expect(bad.reload.optimized_at).to be_nil # skipped, not stamped
    expect(good.reload.optimized_at).to be_present # the run continued
  end
end
