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
    %w[image/jpeg image/png image/webp].each do |type|
      media = build(:media)
      media.image.attach(io: StringIO.new("bytes"), filename: "photo", content_type: type)
      expect(media).to be_valid, "expected #{type} to be accepted"
    end
  end

  it "rejects GIF (providers reject animated GIFs and a MIME check can't tell them apart)" do
    media = build(:media)
    media.image.attach(io: StringIO.new("bytes"), filename: "photo.gif", content_type: "image/gif")
    expect(media).not_to be_valid
    expect(media.errors.where(:image, :unsupported_format)).to be_present
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

  it "rejects an image over the size limit (storage backstop)" do
    stub_const("Media::MAX_IMAGE_BYTES", 5)
    media = build(:media) # factory attaches a real PNG > 5 bytes
    expect(media).not_to be_valid
    expect(media.errors.where(:image, :too_large)).to be_present
  end

  describe "#recognition_state" do
    it "reflects the latest run's status" do
      media = create(:media)
      create(:recognition_run, :failed, media:, move: media.move, box: media.box)
      create(:recognition_run, :succeeded, media:, move: media.move, box: media.box)
      expect(media.recognition_state).to eq("succeeded")
    end
  end

  describe "#sourced_item? / #orphaned?" do
    # #198 — a soft-deleted item still sources its photo, so discarding it must not
    # re-flag the photo as orphaned (which would offer recovery and let it
    # re-source a duplicate, then leave two items on restore).
    it "still counts a discarded item as sourcing the photo" do
      media = create(:media)
      item = create(:item, :manual, move: media.move, box: media.box, source_media: media)
      item.discard!

      aggregate_failures do
        expect(media.reload.sourced_item?).to be(true)
        expect(media.orphaned?).to be(false)
      end
    end
  end

  describe "#image_displayable? (#563)" do
    it "is true for a ready media with a readable master" do
      expect(create(:media)).to be_image_displayable
    end

    it "is false when the master is flagged unavailable" do
      media = create(:media, image_unavailable: true)
      expect(media).not_to be_image_displayable
      expect(media).to be_image_unavailable
    end

    it "is false for a pending media with no image yet" do
      expect(build(:media, :pending)).not_to be_image_displayable
    end
  end
end
