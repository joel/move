require "rails_helper"

RSpec.describe Vocabularies::Remove do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

  it "removes a category and nullifies it on its items (the items survive)" do
    category = create(:category, move:, name: "Books")
    item = create(:item, move:, category:)
    vocabulary = Vocabulary.find("categories")

    result = described_class.new.call(record: category, vocabulary:, actor:)

    expect(result).to be_success
    expect(result.value!).to eq(1) # detached count
    expect(Category.exists?(category.id)).to be(false)
    expect(item.reload.category_id).to be_nil
  end

  it "removes a room and nullifies it on its boxes" do
    room = create(:room, move:)
    box = create(:box, move:, room:)
    vocabulary = Vocabulary.find("rooms")

    described_class.new.call(record: room, vocabulary:, actor:)

    expect(box.reload.room_id).to be_nil
  end

  it "removes a tag and drops the join rows but keeps the items" do
    tag = create(:tag, move:)
    item = create(:item, move:)
    create(:item_tag, item:, tag:)
    vocabulary = Vocabulary.find("tags")

    described_class.new.call(record: tag, vocabulary:, actor:)

    expect(Tag.exists?(tag.id)).to be(false)
    expect(Item.exists?(item.id)).to be(true)
    expect(item.reload.tags).to be_empty
  end

  it "reports a zero detached count for an unused value" do
    room = create(:room, move:)
    vocabulary = Vocabulary.find("rooms")

    expect(described_class.new.call(record: room, vocabulary:, actor:).value!).to eq(0)
  end

  it "emits a vocabulary.removed event with the detached count" do
    allow(Rails.event).to receive(:notify)
    category = create(:category, move:)
    create(:item, move:, category:)
    vocabulary = Vocabulary.find("categories")

    described_class.new.call(record: category, vocabulary:, actor:)

    expect(Rails.event).to have_received(:notify).with(
      "vocabulary.removed", hash_including(kind: "categories", detached_count: 1)
    )
  end
end
