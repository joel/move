require "rails_helper"

RSpec.describe MediaVariants::TransformUrl do
  let(:media) { create(:media) }

  def query(url)
    URI.decode_www_form(URI.parse(url).query).to_h
  end

  # SIZES is now the SOLE source of truth for display geometry — the in-app Active
  # Storage variants (and MediaVariants::Prewarm) were decommissioned in #572, so
  # Media#image declares no named variants any more.
  it "declares exactly the thumb + detail sizes, and Media#image has no in-app variants" do
    expect(described_class::SIZES.keys).to contain_exactly(:thumb, :detail)
    expect(Media.reflect_on_attachment(:image).named_variants).to be_empty
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
      params = query(described_class.for(media, :detail))
      expected = OpenSSL::HMAC.hexdigest(
        "SHA256", "s3cr3t", "#{media.image.blob.key}|detail|#{params.fetch("exp")}"
      )
      expect(params.fetch("t")).to eq(expected)
    end

    # The expiry is QUANTIZED to EXPIRY_BUCKET boundaries so every render inside
    # one bucket mints byte-identical URLs — that identity is what lets the
    # browser reuse its immutable-cached copy across page visits instead of
    # refetching every image on every navigation (#669). Expectations pin
    # INDEPENDENT literals (not the production formula) so a shared arithmetic
    # bug cannot self-confirm: 24h buckets align to UTC midnight, so a mint any
    # time on 2026-07-16 must carry exp = 2026-07-17 02:00 UTC (midnight + 26h).
    describe "expiry quantization (browser-cacheable URLs)" do
      it "mints byte-identical URLs across renders within one bucket" do
        travel_to Time.utc(2026, 7, 16, 0, 0, 1) do
          first = described_class.for(media, :thumb)
          travel 4.hours
          expect(described_class.for(media, :thumb)).to eq(first)
          travel_to Time.utc(2026, 7, 16, 23, 59, 59)
          expect(described_class.for(media, :thumb)).to eq(first)
        end
      end

      it "mints a different URL once the bucket rolls over" do
        travel_to Time.utc(2026, 7, 16, 12) do
          first = described_class.for(media, :thumb)
          travel_to Time.utc(2026, 7, 17, 0, 0, 0)
          expect(described_class.for(media, :thumb)).not_to eq(first)
        end
      end

      it "sets exp to the UTC bucket start plus the 26h TTL" do
        travel_to Time.utc(2026, 7, 16, 12) do
          expect(query(described_class.for(media, :thumb)).fetch("exp").to_i)
            .to eq(Time.utc(2026, 7, 17, 2).to_i)
        end
      end

      it "keeps at least a 2h validity floor for a URL minted at the very end of a bucket" do
        travel_to Time.utc(2026, 7, 16, 23, 59, 59) do
          exp = query(described_class.for(media, :thumb)).fetch("exp").to_i
          expect(exp - Time.current.to_i).to be >= 2.hours.to_i
        end
      end

      it "enforces TTL > EXPIRY_BUCKET so late-bucket mints can never be already expired" do
        expect(described_class::TTL).to be > described_class::EXPIRY_BUCKET
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
