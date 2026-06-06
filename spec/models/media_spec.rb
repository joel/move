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

  describe "#recognition_state" do
    it "reflects the latest run's status" do
      media = create(:media)
      create(:recognition_run, :failed, media:, move: media.move, box: media.box)
      create(:recognition_run, :succeeded, media:, move: media.move, box: media.box)
      expect(media.recognition_state).to eq("succeeded")
    end
  end
end
