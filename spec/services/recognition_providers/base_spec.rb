# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders::Base do
  subject(:provider) { described_class.new }

  describe "#prompt" do
    it "names the room when present, and asks for one entry per distinct item" do
      text = provider.send(:prompt, { room: "Kitchen" })

      expect(text).to include("The box is in the Kitchen.")
      expect(text).to include("Give one entry per distinct item")
    end

    it "omits the room line when no room is set" do
      text = provider.send(:prompt, { room: nil })

      expect(text).not_to include("The box is in")
    end

    it "no longer asks the model about category, tags or fragility (item is name-only)" do
      text = provider.send(:prompt, { room: "Kitchen" })

      expect(text).not_to match(/categor/i)
      expect(text).not_to match(/\btags?\b/i)
      expect(text).not_to match(/fragile/i)
    end

    it "excludes the structural surroundings that leaked into the inventory" do
      # Regression: "floor" and the cardboard "box" kept showing up as items.
      text = provider.send(:prompt, { room: "Kitchen" })

      expect(text).to match(/do not list/i)
      expect(text).to include("floor").and include("box")
      expect(text).to match(/packing materials/i)
    end

    it "asks for a hidden family with consistent wording, empty when unsure (#626)" do
      text = provider.send(:prompt, { room: "Kitchen" })

      expect(text).to include("also give a family")
      expect(text).to include("same family wording")
      expect(text).to match(/leave family empty/i)
    end
  end

  describe "#normalize" do
    it "parses label + confidence, dropping blank labels and clamping confidence" do
      detected = provider.send(:normalize, [
                                 { "label" => "Mug", "confidence" => 1.4 },
                                 { "label" => " ", "confidence" => 0.5 }
                               ])

      expect(detected.size).to eq(1)
      expect(detected.first).to have_attributes(label: "Mug", confidence: 1.0)
    end

    it "keeps a stripped family and maps a blank one (unsure model) to nil" do
      detected = provider.send(:normalize, [
                                 { "label" => "AA batteries", "family" => " batteries & power " },
                                 { "label" => "Mystery object", "family" => "" },
                                 { "label" => "Old radio" }
                               ])

      expect(detected.map(&:family)).to eq(["batteries & power", nil, nil])
    end
  end

  describe "#encoded_image" do
    # A 2400x1200 JPEG stands in for a phone original — bigger than MAX_IMAGE_EDGE.
    let(:big_jpeg) { Vips::Image.black(2400, 1200).jpegsave_buffer }
    let(:image) { instance_double(ActiveStorage::Blob, content_type: "image/jpeg", download: big_jpeg) }

    it "down-scales to <= MAX_IMAGE_EDGE and re-encodes as JPEG" do
      encoded = provider.send(:encoded_image, image)

      expect(encoded[:media_type]).to eq("image/jpeg")
      decoded = Vips::Image.new_from_buffer(Base64.strict_decode64(encoded[:base64]), "")
      expect([decoded.width, decoded.height].max).to be <= RecognitionProviders::Base::MAX_IMAGE_EDGE
    end

    it "falls back to the raw bytes + original content_type when vips can't decode the input" do
      raw = instance_double(ActiveStorage::Blob, content_type: "image/jpeg", download: "not-an-image")

      encoded = provider.send(:encoded_image, raw)

      expect(encoded[:media_type]).to eq("image/jpeg")
      expect(Base64.strict_decode64(encoded[:base64])).to eq("not-an-image")
    end
  end
end
