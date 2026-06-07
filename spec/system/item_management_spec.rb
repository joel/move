# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manual add & item detail" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }
  let(:kitchen) { create(:room, move:, name: "Kitchen") }
  let(:source) { create(:box, move:, number: "1", room: kitchen) }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  it "adds an item manually with category and tags (B3)" do
    create(:category, move:, name: "Kitchenware")
    create(:tag, move:, name: "Heavy")

    visit move_box_path(move, source)
    click_link I18n.t("boxes.actions.add_item")
    fill_in "item[name]", with: "Ceramic Plates"
    select "Kitchenware", from: "item[category_id]"
    check "Heavy"
    click_button I18n.t("items.new.submit")

    expect(page).to have_text("Ceramic Plates")
    item = move.items.find_by!(name: "Ceramic Plates")
    expect(item).to have_attributes(review_state: "confirmed", created_via: "manual")
    expect(item.tags.map(&:name)).to contain_exactly("Heavy")
  end

  it "edits an item from the detail screen (C3)" do
    item = create(:item, :manual, move:, box: source, name: "Old")

    visit move_item_path(move, item)
    fill_in "item[name]", with: "Dinner Plates"
    click_button I18n.t("items.show.save")

    expect(item.reload.name).to eq("Dinner Plates")
  end

  it "moves an item to another box, keeping presence in_box" do
    target = create(:box, move:, number: "2", room: kitchen)
    item = create(:item, :manual, move:, box: source)

    visit move_item_path(move, item)
    select "Box #002 · Kitchen", from: "target_box_id"
    click_button I18n.t("items.show.move")

    expect(item.reload.box).to eq(target)
    expect(item.presence_state).to eq("in_box")
  end

  it "hides the Move control once an item is removed" do
    create(:box, move:, number: "2", room: kitchen)
    item = create(:item, :manual, move:, box: source)

    visit move_item_path(move, item)
    expect(page).to have_button(I18n.t("items.show.move"))

    click_button I18n.t("items.show.remove")
    expect(page).to have_no_button(I18n.t("items.show.move"))
  end

  it "removes then restores an item (presence axis)" do
    item = create(:item, :manual, move:, box: source)

    visit move_item_path(move, item)
    click_button I18n.t("items.show.remove")
    expect(item.reload.presence_state).to eq("removed")

    click_button I18n.t("items.show.restore")
    expect(item.reload.presence_state).to eq("in_box")
  end
end
