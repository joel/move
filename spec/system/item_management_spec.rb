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
    # The box-detail add affordance is the quiet "Add manually" link under the
    # Capture hero (#401).
    click_link I18n.t("boxes.actions.add_manually")
    fill_in "item[name]", with: "Ceramic Plates"
    select "Kitchenware", from: "item[category_id]"
    check "Heavy"
    click_button I18n.t("items.new.submit")

    expect(page).to have_text("Ceramic Plates")
    item = move.items.find_by!(name: "Ceramic Plates")
    expect(item).to have_attributes(review_state: "confirmed", created_via: "manual")
    expect(item.tags.map(&:name)).to contain_exactly("Heavy")
  end

  it "presents the detail screen as an auto-saving form with no Save button (C3)" do
    item = create(:item, :manual, move:, box: source, name: "Old")

    visit move_item_path(move, item)

    # Auto-save (change->auto-submit) is JS-only; the *update* itself is covered by
    # the request spec. Here we assert the redesigned surface: the editable name
    # field is present and there is no "Save Changes" button.
    expect(page).to have_field("item[name]", with: "Old")
    expect(page).to have_no_button(I18n.t("items.show.save"))
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

  it "deletes a mistaken item while packing (restorable via the activity feed)" do
    item = create(:item, :manual, move:, box: source)

    visit move_item_path(move, item)
    expect(page).to have_button(I18n.t("items.show.delete"))
    click_button I18n.t("items.show.delete")

    expect(Item.exists?(item.id)).to be(false)
    expect(Item.with_discarded.find(item.id)).to be_discarded
  end

  it "hides the Move control once an item is marked unpacked" do
    unpacking = create(:box, move:, number: "3", room: kitchen, status: "unpacking")
    create(:box, move:, number: "2", room: kitchen)
    item = create(:item, :manual, move:, box: unpacking)

    visit move_item_path(move, item)
    expect(page).to have_button(I18n.t("items.show.move"))

    click_button I18n.t("items.show.mark_unpacked")
    expect(page).to have_no_button(I18n.t("items.show.move"))
  end

  it "marks unpacked then restores an item (presence axis)" do
    unpacking = create(:box, move:, number: "3", room: kitchen, status: "unpacking")
    item = create(:item, :manual, move:, box: unpacking)

    visit move_item_path(move, item)
    click_button I18n.t("items.show.mark_unpacked")
    expect(item.reload.presence_state).to eq("removed")

    click_button I18n.t("items.show.restore")
    expect(item.reload.presence_state).to eq("in_box")
  end
end
