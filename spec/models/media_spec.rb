# frozen_string_literal: true

require "rails_helper"

RSpec.describe Media do
  it "has a valid factory with an attached image" do
    media = build(:media)
    expect(media).to be_valid
    expect(media.image).to be_attached
  end

  it "requires an attached image, a known type and capture source" do
    media = build(:media, media_type: "video", captured_via: "carrier_pigeon")
    media.image.detach
    expect(media).not_to be_valid
    expect(media.errors.attribute_names).to include(:image, :media_type, :captured_via)
  end

  it "accepts the formats the recognition providers can read" do
    %w[image/jpeg image/png image/webp image/gif].each do |type|
      media = build(:media)
      media.image.attach(io: StringIO.new("bytes"), filename: "photo", content_type: type)
      expect(media).to be_valid, "expected #{type} to be accepted"
    end
  end

  it "rejects an image format the providers can't read (e.g. HEIC) at upload" do
    media = build(:media)
    media.image.attach(io: StringIO.new("bytes"), filename: "photo.heic", content_type: "image/heic")
    expect(media).not_to be_valid
    expect(media.errors.where(:image, :unsupported_format)).to be_present
  end

  it "rejects a non-image upload" do
    media = build(:media)
    media.image.attach(io: StringIO.new("nope"), filename: "doc.pdf", content_type: "application/pdf")
    expect(media).not_to be_valid
    expect(media.errors.where(:image, :not_an_image)).to be_present
  end

  describe "#recognition_state" do
    it "reflects the latest run's status" do
      media = create(:media)
      create(:recognition_run, :failed, media:, move: media.move, box: media.box)
      create(:recognition_run, :succeeded, media:, move: media.move, box: media.box)
      expect(media.recognition_state).to eq("succeeded")
    end
  end
end
