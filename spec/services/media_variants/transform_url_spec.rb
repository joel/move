require "rails_helper"

RSpec.describe MediaVariants::TransformUrl do
  let(:media) { create(:media) }

  def query(url)
    URI.decode_www_form(URI.parse(url).query).to_h
  end

  it "exposes the same sizes declared on Media#image (kept in sync with Prewarm)" do
    declared = Media.reflect_on_attachment(:image).named_variants.keys
    expect(described_class::SIZES.keys).to match_array(declared)
    expect(described_class::SIZES.keys).to match_array(MediaVariants::Prewarm::VARIANTS)
  end

  # The Worker (workers/media-transform/src/index.js) carries a hardcoded copy of
  # these exact values. Pin them here so a Rails-side drift is caught by CI; the
  # Worker copy must be updated in lockstep (its comment cross-references this).
  it "pins the transform geometry the Worker mirrors" do
    expect(described_class::SIZES).to eq(
      thumb: { width: 400, height: 400, fit: "scale-down" },
      detail: { width: 1600, height: 1600, fit: "scale-down" }
    )
  end

  context "when MEDIA_TRANSFORM_HOST is configured (prod-like)" do
    around do |example|
      original_host = Rails.application.config.x.media_transform_host
      original_secret = Rails.application.config.x.media_transform_secret
      Rails.application.config.x.media_transform_host = "media.example.org"
      Rails.application.config.x.media_transform_secret = "s3cr3t"
      example.run
      Rails.application.config.x.media_transform_host = original_host
      Rails.application.config.x.media_transform_secret = original_secret
    end

    it "builds a Worker URL keyed by size and blob key" do
      url = described_class.for(media, :thumb)
      expect(url).to start_with("https://media.example.org/thumb/#{media.image.blob.key}?")
    end

    it "signs the canonical 'blob_key|size|exp' string with the dedicated secret" do
      freeze_time do
        exp = 1.hour.from_now.to_i
        token = query(described_class.for(media, :detail)).fetch("t")
        expected = OpenSSL::HMAC.hexdigest("SHA256", "s3cr3t", "#{media.image.blob.key}|detail|#{exp}")
        expect(token).to eq(expected)
      end
    end

    it "defaults the expiry to one hour out" do
      freeze_time do
        expect(query(described_class.for(media, :thumb)).fetch("exp").to_i).to eq(1.hour.from_now.to_i)
      end
    end

    it "honours a custom ttl" do
      freeze_time do
        expect(query(described_class.for(media, :thumb, ttl: 5.minutes)).fetch("exp").to_i)
          .to eq(5.minutes.from_now.to_i)
      end
    end

    it "binds the token to the size — thumb and detail differ for the same media" do
      expect(described_class.for(media, :thumb)).not_to eq(described_class.for(media, :detail))
    end

    it "raises for an unknown size (a programmer error)" do
      expect { described_class.for(media, :huge) }.to raise_error(ArgumentError, /unknown transform size/)
    end

    it "raises loudly rather than mint an unsigned URL when the secret is missing" do
      Rails.application.config.x.media_transform_secret = nil
      expect { described_class.for(media, :thumb) }.to raise_error(/MEDIA_TRANSFORM_SECRET/)
    end
  end

  context "when MEDIA_TRANSFORM_HOST is unset (dev/test default)" do
    around do |example|
      original = Rails.application.config.x.media_transform_host
      Rails.application.config.x.media_transform_host = nil
      example.run
      Rails.application.config.x.media_transform_host = original
    end

    it "falls back to the proxied master, not an edge URL or a variant" do
      url = described_class.for(media, :thumb)
      expect(url).to include("/rails/active_storage/")
      expect(url).not_to include("media.example.org")
      expect(url).not_to match(%r{/(thumb|detail)/})
    end
  end

  it "returns nil for a media with no displayable image" do
    expect(described_class.for(build(:media, with_image: false), :thumb)).to be_nil
    expect(described_class.for(nil, :thumb)).to be_nil
  end
end
