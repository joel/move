# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seed_data/catalog").to_s

# Integrity checks for the demo catalog that db/seeds.rb and seed_images:generate
# both read. These guard the invariants the seed relies on (valid enum values,
# vocabulary references, unique image slugs) so a typo fails here, not mid-seed.
RSpec.describe SeedData do
  # The vocabularies the seed actually creates: the curated defaults + the
  # demo-only "Everyday Use" tag added in db/seeds.rb. Box-only tags can't tag
  # items, so they're excluded from the item-taggable set.
  def known_categories = Moves::DefaultVocabularies::CATEGORIES

  def item_taggable
    Moves::DefaultVocabularies::TAGS.reject { |_name, applies| applies == "box" }.keys + ["Everyday Use"]
  end

  def box_numbers = SeedData::BOXES.pluck(:number)

  describe "BOXES" do
    it "has unique numbers" do
      expect(box_numbers.uniq).to eq(box_numbers)
    end

    it "only uses valid statuses and known rooms" do
      SeedData::BOXES.each do |box|
        expect(Box::STATUSES).to include(box[:status]), "box #{box[:number]} status"
        next unless box[:room]

        expect(Moves::DefaultVocabularies::ROOMS).to include(box[:room]), "box #{box[:number]} room"
      end
    end

    it "covers every box lifecycle status (the showcase mandate)" do
      statuses = SeedData::BOXES.pluck(:status)
      expect(statuses.uniq).to match_array(Box::STATUSES)
    end
  end

  describe "PHOTOS" do
    it "has unique image slugs" do
      slugs = SeedData::PHOTOS.pluck(:slug)
      expect(slugs.uniq).to eq(slugs)
    end

    it "references existing boxes and a non-blank prompt" do
      SeedData::PHOTOS.each do |photo|
        expect(box_numbers).to include(photo[:box]), "photo #{photo[:slug]} box"
        expect(photo[:prompt]).to be_present, "photo #{photo[:slug]} prompt"
      end
    end

    it "uses a valid status; failed/empty carry no items" do
      SeedData::PHOTOS.each do |photo|
        expect(%w[succeeded failed empty]).to include(photo[:status]), "photo #{photo[:slug]} status"
        expect(photo[:items]).to be_empty if photo[:status] != "succeeded"
      end
    end

    it "failed photos carry an error code and message" do
      SeedData::PHOTOS.select { |photo| photo[:status] == "failed" }.each do |photo|
        expect(photo[:error_code]).to be_present, "photo #{photo[:slug]} error_code"
        expect(photo[:error_message]).to be_present, "photo #{photo[:slug]} error_message"
      end
    end

    it "only uses valid item enum values and known vocabulary" do
      photo_items = SeedData::PHOTOS.flat_map { |photo| photo[:items] }
      expect(photo_items).not_to be_empty
      photo_items.each { |item| expect_valid_item(item) }
    end
  end

  describe "MANUAL_ITEMS" do
    it "references existing boxes" do
      SeedData::MANUAL_ITEMS.each do |item|
        expect(box_numbers).to include(item[:box]), "manual item #{item[:name]} box"
      end
    end

    it "only uses valid item enum values and known vocabulary" do
      SeedData::MANUAL_ITEMS.each { |item| expect_valid_item(item) }
    end
  end

  describe ".normalize_recorded" do
    subject(:detections) { described_class.normalize_recorded(objects, threshold: 0.8) }

    let(:objects) do
      [
        { "label" => "Coffee maker", "confidence" => 0.95, "count" => 0, "category" => "Appliances",
          "tags" => [] },
        { "label" => "Wine glasses", "confidence" => 0.4, "count" => 6, "category" => "Kitchenware",
          "tags" => [" Valuable ", "Valuable", ""] },
        { "label" => "  ", "confidence" => 0.9, "count" => 1, "category" => "x", "tags" => [] }
      ]
    end

    it "drops blank labels" do
      expect(detections.pluck(:name)).to eq(["Coffee maker", "Wine glasses"])
    end

    it "splits review_state on the auto-confirm threshold" do
      expect(detections.first[:review]).to eq("auto_confirmed")  # 0.95 >= 0.8
      expect(detections.last[:review]).to eq("pending_review")   # 0.40 < 0.8
    end

    it "strips, blank-drops and dedupes tags" do
      expect(detections.last[:tags]).to eq(["Valuable"])
    end
  end

  describe ".detections_for" do
    it "falls back to the authored items when no recording is committed" do
      photo = SeedData::PHOTOS.find { |p| p[:slug] == "kitchen-counter" }
      allow(described_class).to receive(:recorded_recognition).with("kitchen-counter").and_return(nil)

      detections = described_class.detections_for(photo, threshold: 0.8)
      expect(detections.pluck(:name)).to eq(photo[:items].pluck(:name))
      expect(detections.pluck(:review)).to eq(photo[:items].pluck(:review))
    end

    it "uses the recorded objects when present" do
      photo = SeedData::PHOTOS.find { |p| p[:slug] == "kitchen-counter" }
      allow(described_class).to receive(:recorded_recognition).with("kitchen-counter").and_return(
        "objects" => [{ "label" => "Kettle", "confidence" => 0.9, "count" => 1,
                        "category" => "Appliances", "tags" => [] }]
      )

      detections = described_class.detections_for(photo, threshold: 0.8)
      expect(detections.pluck(:name)).to eq(["Kettle"])
    end
  end

  it "every succeeded photo has authored fallback items; recovery tiles have none" do
    SeedData::PHOTOS.each do |photo|
      if photo[:status] == "succeeded"
        expect(photo[:items]).not_to be_empty, "#{photo[:slug]} fallback items"
      else
        expect(photo[:items]).to be_empty, "#{photo[:slug]} (#{photo[:status]}) items"
      end
    end
  end

  def expect_valid_item(item)
    label = item[:name]
    expect(label).to be_present
    expect(Item::REVIEW_STATES).to include(item[:review]), "#{label} review"
    expect(Item::PRESENCE_STATES).to include(item[:presence] || "in_box"), "#{label} presence"
    expect(known_categories).to include(item[:category]) if item[:category]
    (item[:tags] || []).each do |tag|
      expect(item_taggable).to include(tag), "#{label} tag #{tag}"
    end
  end
end
