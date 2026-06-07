require "rails_helper"

RSpec.describe Vocabularies::Update do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

  it "renames a value and the rename propagates to associated records" do
    category = create(:category, move:, name: "Bookz")
    item = create(:item, move:, category:)
    vocabulary = Vocabulary.find("categories")

    result = described_class.new.call(record: category, vocabulary:, params: { name: "Books" }, actor:)

    expect(result).to be_success
    expect(category.reload.name).to eq("Books")
    expect(item.reload.category.name).to eq("Books")
  end

  it "edits a tag's applies_to facet" do
    tag = create(:tag, move:, applies_to: "item")
    vocabulary = Vocabulary.find("tags")

    described_class.new.call(record: tag, vocabulary:, params: { name: tag.name, applies_to: "box" }, actor:)

    expect(tag.reload.applies_to).to eq("box")
  end

  it "detaches item associations when a tag is narrowed to box-only" do
    tag = create(:tag, move:, applies_to: "both")
    item = create(:item, move:)
    create(:item_tag, item:, tag:)
    vocabulary = Vocabulary.find("tags")

    result = described_class.new.call(
      record: tag, vocabulary:, params: { name: tag.name, applies_to: "box" }, actor:
    )

    expect(result).to be_success
    expect(item.reload.tags).to be_empty
    expect(Item.exists?(item.id)).to be(true)
  end

  it "keeps item associations when a tag stays item-assignable" do
    tag = create(:tag, move:, applies_to: "item")
    item = create(:item, move:)
    create(:item_tag, item:, tag:)
    vocabulary = Vocabulary.find("tags")

    described_class.new.call(record: tag, vocabulary:, params: { name: "Renamed", applies_to: "both" }, actor:)

    expect(item.reload.tags).to contain_exactly(tag)
  end

  it "returns validation errors for a blank name" do
    room = create(:room, move:)
    vocabulary = Vocabulary.find("rooms")

    result = described_class.new.call(record: room, vocabulary:, params: { name: "" }, actor:)

    expect(result).to be_failure
    expect(result.failure).to be_a(ActiveModel::Errors)
  end

  it "emits a vocabulary.updated event" do
    allow(Rails.event).to receive(:notify)
    category = create(:category, move:)
    vocabulary = Vocabulary.find("categories")

    described_class.new.call(record: category, vocabulary:, params: { name: "Renamed" }, actor:)

    expect(Rails.event).to have_received(:notify).with(
      "vocabulary.updated", hash_including(kind: "categories", record_id: category.id)
    )
  end
end
