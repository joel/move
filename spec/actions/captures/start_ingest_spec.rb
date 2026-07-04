# frozen_string_literal: true

require "rails_helper"

# #545 — the async web capture entry point: creates a PENDING, image-less Media
# and enqueues Captures::IngestJob to do the heavy lifting (normalize/attach/
# recognise) off the request. The job is stubbed here so these specs assert the
# request-time contract only (fast, no libvips) — the job's own work is covered
# by spec/jobs/captures/ingest_job_spec.rb.
RSpec.describe Captures::StartIngest do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:, number: "1", status: "packing") }

  before { allow(Captures::IngestJob).to receive(:perform_later) }

  def upload(name = "sample_image.png", type = "image/png")
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files", name), type)
  end

  it "creates a pending, image-less media and enqueues ingest off the request" do
    result = nil
    expect { result = described_class.new.call(box:, file: upload, captured_by: user) }
      .to change(box.media.pending, :count).by(1)

    media = result.value!
    expect(media).to be_pending
    expect(media.image).not_to be_attached
    expect(media.captured_via).to eq("web")
    expect(Captures::IngestJob).to have_received(:perform_later)
      .with(media.id, anything, hash_including(captured_by_id: user.id, tenant: Apartment::Tenant.current))
  end

  it "rejects a non-raster image (SVG) up front — no orphaned row" do
    expect do
      result = described_class.new.call(box:, file: upload("sample.svg", "image/svg+xml"), captured_by: user)
      expect(result.failure).to eq(:unsupported_image)
    end.not_to change(Media, :count)
    expect(Captures::IngestJob).not_to have_received(:perform_later)
  end

  it "rejects an oversized upload up front" do
    stub_const("Media::MAX_IMAGE_BYTES", 5)
    expect do
      result = described_class.new.call(box:, file: upload, captured_by: user)
      expect(result.failure).to eq(:image_too_large)
    end.not_to change(Media, :count)
  end

  it "fails a no-file submission" do
    result = described_class.new.call(box:, file: nil, captured_by: user)
    expect(result.failure).to eq(:no_file)
  end

  it "blocks a sealed (non-capturable) box" do
    sealed = create(:box, :with_room, move:, status: "sealed")
    result = described_class.new.call(box: sealed, file: upload, captured_by: user)
    expect(result.failure).to eq(:not_capturable)
  end
end
