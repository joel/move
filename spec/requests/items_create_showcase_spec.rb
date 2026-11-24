# frozen_string_literal: true

require "rails_helper"

# #958 — UX rule 1: a manually added item must not land silently off-screen.
RSpec.describe "Items create showcase (#958)" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  it "links the toast to the new item and flags it for a one-time highlight" do
    post move_box_items_path(move, box), params: { item: { name: "Lamp" } }
    item = box.items.last

    expect(flash[:action_href]).to eq(move_item_path(move, item))
    expect(flash[:action_label]).to eq(I18n.t("items.create.view_item"))
    expect(flash[:highlight_item_id]).to eq(item.id)
  end

  it "shows a toast linking to the new item" do
    post move_box_items_path(move, box), params: { item: { name: "Lamp" } }
    item = box.items.last
    follow_redirect!

    toasts = response.parsed_body.at_css("##{Components::FlashToasts::ID}")
    expect(toasts.text).to include(I18n.t("items.create.created", name: "Lamp"))
    expect(toasts.at_css("a[href='#{move_item_path(move, item)}']").text)
      .to include(I18n.t("items.create.view_item"))
  end

  it "renders the new item's card with the highlight controller on the box page" do
    create_list(:media, 4, move:, box:)
    post move_box_items_path(move, box), params: { item: { name: "Lamp" } }
    item = box.items.last
    follow_redirect!

    card = response.parsed_body.at_css("##{Components::Boxes::ItemCard.dom_id(item)}")
    expect(card).to be_present
    expect(card["data-controller"].to_s.split).to include("highlight")
  end

  it "highlights only the new card, and only once" do
    older = create(:item, :manual, move:, box:, name: "Vase")
    post move_box_items_path(move, box), params: { item: { name: "Lamp" } }
    follow_redirect!

    doc = response.parsed_body
    expect(doc.css("[data-controller~='highlight']").size).to eq(1)
    expect(doc.at_css("##{Components::Boxes::ItemCard.dom_id(older)}")["data-controller"]).to be_nil

    get move_box_path(move, box)
    expect(response.parsed_body.css("[data-controller~='highlight']")).to be_empty
  end

  it "leaves the closed-box refusal unlinked and unhighlighted" do
    sealed = create(:box, move:, status: "sealed")
    post move_box_items_path(move, sealed), params: { item: { name: "Lamp" } }

    expect(flash[:alert]).to eq(I18n.t("items.create.box_closed"))
    expect(flash[:action_href]).to be_nil
    expect(flash[:highlight_item_id]).to be_nil
  end
end
