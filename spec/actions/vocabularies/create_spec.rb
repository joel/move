require "rails_helper"

RSpec.describe Vocabularies::Create do
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }

  it "adds a category by name" do
    vocabulary = Vocabulary.find("categories")

    result = described_class.new.call(move:, vocabulary:, params: { name: "Books" }, actor:)

    expect(result).to be_success
    expect(result.value!).to be_a(Category).and have_attributes(name: "Books", move:)
  end

  it "adds a tag with an applies_to facet" do
    vocabulary = Vocabulary.find("tags")

    tag = described_class.new.call(
      move:, vocabulary:, params: { name: "Fragile", applies_to: "both" }, actor:
    ).value!

    expect(tag).to be_a(Tag).and have_attributes(name: "Fragile", applies_to: "both")
  end

  it "ignores unpermitted params (no free-text applies_to on rooms)" do
    vocabulary = Vocabulary.find("rooms")

    room = described_class.new.call(
      move:, vocabulary:, params: { name: "Garage", applies_to: "both" }, actor:
    ).value!

    expect(room).to be_a(Room)
    expect(room).not_to respond_to(:applies_to)
  end

  it "returns validation errors for a blank name" do
    vocabulary = Vocabulary.find("categories")

    result = described_class.new.call(move:, vocabulary:, params: { name: "" }, actor:)

    expect(result).to be_failure
    expect(result.failure).to be_a(ActiveModel::Errors)
    expect(move.categories.count).to eq(0)
  end

  it "rejects a case-variant duplicate" do
    create(:category, move:, name: "Books")
    vocabulary = Vocabulary.find("categories")

    result = described_class.new.call(move:, vocabulary:, params: { name: "books" }, actor:)

    expect(result).to be_failure
  end

  it "surfaces a unique-index race as a taken name, not a 500" do
    vocabulary = Vocabulary.find("categories")
    relation = move.categories
    record = build(:category, move:, name: "Books")
    allow(record).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)
    allow(vocabulary).to receive(:records).with(move).and_return(relation)
    allow(relation).to receive(:new).and_return(record)

    result = described_class.new.call(move:, vocabulary:, params: { name: "Books" }, actor:)

    expect(result).to be_failure
    expect(result.failure).to be_a(ActiveModel::Errors)
    expect(result.failure[:name]).to be_present
  end

  it "emits a vocabulary.created event" do
    allow(Rails.event).to receive(:notify)
    vocabulary = Vocabulary.find("rooms")

    described_class.new.call(move:, vocabulary:, params: { name: "Attic" }, actor:)

    expect(Rails.event).to have_received(:notify).with(
      "vocabulary.created", hash_including(kind: "rooms", move_id: move.id)
    )
  end
end
