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
end
