require "rails_helper"

RSpec.describe Searches::ExampleQueries do
  let(:move) { create(:move) }
  let(:kitchen) { create(:room, move:, name: "Kitchen") }
  let(:office) { create(:room, move:, name: "Office") }

  def add_items(room, *names, **attrs)
    box = create(:box, move:, room:)
    names.each { |name| create(:item, :confirmed, move:, box:, name:, **attrs) }
  end

  it "ranks the busiest rooms first, then the most common item names, capped at three" do
    add_items(office, "Stapler")
    add_items(kitchen, "Mug", "Mug", "Kettle")

    expect(described_class.new(move).list).to eq(%w[Kitchen Office Mug])
  end

  it "counts only searchable items" do
    add_items(office, "Lamp", review_state: "needs_correction")

    expect(described_class.new(move).list).to eq([])
  end

  it "leaves out the excluded query, case-insensitively" do
    add_items(kitchen, "Kettle")

    expect(described_class.new(move, exclude: " kitchen ").list).to eq(["Kettle"])
  end

  it "does not repeat a name shared by a room and an item" do
    add_items(office, "office")

    expect(described_class.new(move).list).to eq(["Office"])
  end
end
