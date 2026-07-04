# frozen_string_literal: true

require "rails_helper"

# #545 — the background half of async capture: normalize the reserved raw blob,
# attach the master, flip pending → ready, enqueue recognition. The happy path
# needs libvips (CI only, like the other ImageNormalizer specs); the failure and
# idempotency paths do not.
RSpec.describe Captures::IngestJob do
  let(:tenant) { Apartment::Tenant.current }
  let(:move) { create(:move) }
  let(:box) { create(:box, move:, status: "packing") }

  def raw_blob(name = "sample_image.png", type = "image/png")
    ActiveStorage::Blob.create_and_upload!(
      io: Rails.root.join("spec/fixtures/files", name).open,
      filename: name, content_type: type, identify: false
    )
  end

  it "runs on the dedicated image_ingest pool (#543)" do
    expect(described_class.new.queue_name).to eq("image_ingest")
  end

  it "normalizes, attaches the master, and flips the media to ready" do
    media = create(:media, :pending, box:, move:)
    blob = raw_blob

    described_class.perform_now(media.id, blob.id, captured_by_id: nil, tenant:)

    media.reload
    expect(media).to be_ready
    expect(media.image).to be_attached
    expect(media.image.content_type).to eq("image/jpeg")
    expect(media.recognition_runs).to be_any # recognition was enqueued+run (inline test adapter)
  end

  it "marks the media failed when the reserved blob is gone (never a stuck placeholder)" do
    blob = raw_blob
    blob_id = blob.id
    blob.purge
    media = create(:media, :pending, box:, move:)

    expect { described_class.perform_now(media.id, blob_id, captured_by_id: nil, tenant:) }
      .to change { media.reload.status }.from("pending").to("failed")
  end

  it "is idempotent — a retry once the media has left pending no-ops" do
    media = create(:media, box:, move:) # already ready
    blob = raw_blob

    expect { described_class.perform_now(media.id, blob.id, captured_by_id: nil, tenant:) }
      .not_to(change { media.reload.status })
  end

  it "is safe when the media was since deleted" do
    blob = raw_blob
    expect { described_class.perform_now(SecureRandom.uuid, blob.id, captured_by_id: nil, tenant:) }
      .not_to raise_error
  end
end
