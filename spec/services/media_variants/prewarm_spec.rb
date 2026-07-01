require "rails_helper"

RSpec.describe MediaVariants::Prewarm do
  let(:media) { create(:media) }

  it "stays in sync with the variants declared on Media#image" do
    declared = Media.reflect_on_attachment(:image).named_variants.keys
    expect(described_class::VARIANTS).to match_array(declared)
  end

  it "warms every declared display variant and returns the count" do
    expect { expect(described_class.call(media)).to eq(described_class::VARIANTS.size) }
      .to change(ActiveStorage::VariantRecord, :count).by(described_class::VARIANTS.size)
  end

  it "is idempotent — a second run re-creates no variant records" do
    described_class.call(media)

    expect { described_class.call(media) }.not_to change(ActiveStorage::VariantRecord, :count)
    expect(described_class.call(media)).to eq(described_class::VARIANTS.size)
  end

  it "no-ops for missing or unattached media" do
    expect(described_class.call(nil)).to eq(0)
    expect(described_class.call(Media.new)).to eq(0)
  end

  it "skips a variant whose transform fails (storage OR libvips), without raising" do
    # A corrupt master raises a libvips/ImageProcessing error, not an
    # ActiveStorage::Error — the rescue must be broad so the job can't loop forever.
    allow(media.image).to receive(:variant).and_raise(RuntimeError, "vips decode failed")

    expect { expect(described_class.call(media)).to eq(0) }.not_to raise_error
  end

  describe "repair mode (#486)" do
    let(:master) { media.image.blob }
    let(:thumb_digest) { media.image.variant(:thumb).variation.digest }

    def thumb_blob
      media.image.variant(:thumb).processed.image.blob
    end

    # Read the persisted variant record's file straight from storage — WITHOUT
    # calling `.processed` (which would lazily rebuild and mask a no-op repair).
    def persisted_thumb_file_present?
      rec = ActiveStorage::VariantRecord.find_by(blob_id: master.id, variation_digest: thumb_digest)
      rec.present? && rec.image.blob.service.exist?(rec.image.blob.key)
    end

    it "rebuilds a variant whose file has gone missing from storage" do
      described_class.call(media) # warm both variants
      orphaned = thumb_blob
      # Simulate isolated object-store loss: file gone, record row still present.
      orphaned.service.delete(orphaned.key)
      expect(orphaned.service.exist?(orphaned.key)).to be(false)

      # Plain prewarm can't fix it — .processed only checks the row exists.
      expect(described_class.call(media)).to eq(described_class::VARIANTS.size)
      expect(orphaned.service.exist?(orphaned.key)).to be(false)

      # Repair on a media loaded the way images:repair loads it (variant_records
      # PRELOADED) — the path where a naive destroy leaves a stale in-memory record.
      loaded = Media.with_attached_image.find(media.id)
      expect(described_class.call(loaded, repair: true)).to eq(described_class::VARIANTS.size)

      # The repair itself must have rebuilt the file — asserted on persisted state.
      expect(persisted_thumb_file_present?).to be(true)
    end

    it "leaves a healthy variant untouched (no needless rebuild)" do
      described_class.call(media)
      before_key = thumb_blob.key

      expect(described_class.call(Media.with_attached_image.find(media.id), repair: true))
        .to eq(described_class::VARIANTS.size)

      expect(media.reload.image.variant(:thumb).processed.image.blob.key).to eq(before_key)
    end

    it "creates missing variants from scratch, like plain prewarm" do
      expect { described_class.call(media, repair: true) }
        .to change(ActiveStorage::VariantRecord, :count).by(described_class::VARIANTS.size)
    end

    it "counts only the variants it actually repaired" do
      described_class.call(media) # warm both
      orphaned = thumb_blob
      orphaned.service.delete(orphaned.key) # break exactly one of the two

      warmer = described_class.new(repair: true)
      warmer.call(Media.with_attached_image.find(media.id))

      expect(warmer.repaired).to eq(1) # only :thumb was orphaned; :detail was healthy
    end

    it "reports zero repairs for a fully healthy media" do
      described_class.call(media)

      warmer = described_class.new(repair: true)
      warmer.call(Media.with_attached_image.find(media.id))

      expect(warmer.repaired).to eq(0)
    end
  end
end
