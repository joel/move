# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecognitionProviders::Base do
  subject(:provider) { described_class.new }

  describe "#prompt" do
    it "folds the move's category + tag vocabulary into the classification instruction" do
      text = provider.send(:prompt, { room: "Kitchen", categories: ["Kitchenware"], tags: ["Heavy"] })

      expect(text).to include("Kitchen")
      expect(text).to include("Kitchenware", "Heavy")
      expect(text).to include("Prefer one of these existing categories")
      expect(text).to match(/fragile/i)
    end

    it "still asks for a category when the move has no vocabulary yet" do
      text = provider.send(:prompt, { room: nil, categories: [], tags: [] })

      expect(text).to include("Classify each item with a concise category")
      expect(text).not_to include("The box is in")
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
