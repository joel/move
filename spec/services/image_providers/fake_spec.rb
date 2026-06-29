# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImageProviders::Fake do
  it "generates a real, attachable PNG with no network call" do
    result = described_class.new.generate(prompt: "a brass lamp")

    expect(result.provider).to eq("fake")
    expect(result.content_type).to eq("image/png")
    expect(result.image_bytes[0, 8].bytes).to eq([137, 80, 78, 71, 13, 10, 26, 10]) # PNG signature
  end
end
