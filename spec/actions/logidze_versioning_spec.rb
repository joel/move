# frozen_string_literal: true

require "rails_helper"

# Logidze field-level versioning wired through the action layer (Technical
# Foundation §6/§7). Edits create attributed versions (the feed's revert source);
# soft-deletes must not churn versions; reverting restores prior field values.
RSpec.describe "Logidze versioning" do # rubocop:disable RSpec/DescribeClass
  let(:actor) { create(:user) }
  let(:move) { create(:move, created_by: actor) }
  let(:item) { create(:item, :manual, move:, name: "Lamp") }

  it "creates a baseline version on insert" do
    expect(item.reload.log_version).to eq(1)
  end

  it "versions an edit and attributes the responsible actor in the meta" do
    Items::Rename.new.call(item:, name: "Desk lamp", editor: actor)

    item.reload
    expect(item.log_version).to eq(2)
    expect(item.log_data.versions.last.meta).to include("_r" => actor.id)
  end

  it "reverts to a prior version's field value" do
    Items::Rename.new.call(item:, name: "Desk lamp", editor: actor)

    expect(item.reload.at(version: 1).name).to eq("Lamp")
  end

  it "does not churn a version when the record is soft-deleted" do
    Items::Rename.new.call(item:, name: "Desk lamp", editor: actor)
    version_before = item.reload.log_version

    Items::Delete.new.call(item:, actor:)

    expect(Item.with_discarded.find(item.id).log_version).to eq(version_before)
  end

  it "rolls back a failed edit without orphaning a created version or row" do
    # An invalid rename (blank name) must not advance the version.
    Items::Rename.new.call(item:, name: "", editor: actor)

    expect(item.reload.log_version).to eq(1)
    expect(item.name).to eq("Lamp")
  end
end
