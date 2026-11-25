# frozen_string_literal: true

require "rails_helper"

# #960 (UX rule 4): the item page's back link returns to the search results or
# find list the user opened it from, via an allow-listed `from` param. Anything
# else falls back to the box, and no URL from params is ever echoed.
RSpec.describe "Item back link" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:, number: "4") }
  let(:item) { create(:item, :confirmed, move:, box:, name: "Cast iron skillet") }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  # The single back link: the anchor that carries the rotated chevron.
  def back_link
    links = response.parsed_body.css("a").select { |a| a.at_css("svg.rotate-180") }
    expect(links.size).to eq(1)
    links.first
  end

  def expect_box_fallback
    expect(response).to have_http_status(:ok)
    expect(back_link["href"]).to eq(move_box_path(move, box))
    expect(back_link.text.strip).to eq(I18n.t("items.show.back"))
  end

  describe "GET /moves/:move_id/items/:id" do
    it "returns to the box with no origin" do
      get move_item_path(move, item)

      expect_box_fallback
    end

    it "returns to the search results, keeping the query and the card anchor" do
      get move_item_path(move, item, from: "search", q: "skillet & pan")

      expect(back_link["href"])
        .to eq(move_search_path(move, q: "skillet & pan", anchor: "search-result-#{item.id}"))
      expect(back_link.text.strip).to eq(I18n.t("items.show.back_to_results"))
    end

    it "returns to the find list, onto the item's row" do
      get move_item_path(move, item, from: "find_list")

      expect(back_link["href"]).to eq(move_find_list_path(move, anchor: "find-list-item-#{item.id}"))
      expect(back_link.text.strip).to eq(I18n.t("items.show.back_to_find_list"))
    end

    it "falls back to the box for a search origin without a query" do
      get move_item_path(move, item, from: "search", q: "  ")

      expect_box_fallback
    end

    it "falls back to the box for an unknown origin" do
      get move_item_path(move, item, from: "gallery")

      expect_box_fallback
    end

    it "never echoes an external or arbitrary URL from params (no open redirect)" do
      ["https://evil.example/phish", "//evil.example", "/moves/other/boxes", "javascript:alert(1)"].each do |value|
        get move_item_path(move, item, from: value, return_to: value, back: value)

        expect_box_fallback
        expect(response.body).not_to include("evil.example")
        expect(response.body).not_to include("javascript:alert")
      end
    end
  end

  describe "origin links" do
    it "tags search result cards with the query and gives each card its anchor" do
      item
      Search::RefreshDocument.new.call(item:)

      get move_search_path(move, q: "skillet")

      card = response.parsed_body.at_css("a#search-result-#{item.id}")
      expect(card["href"]).to eq(move_item_path(move, item, from: "search", q: "skillet"))
    end

    it "tags find-list rows and gives each row its anchor" do
      create(:find_list_entry, move:, user:, item:)

      get move_find_list_path(move)

      row = response.parsed_body.at_css("a#find-list-item-#{item.id}")
      expect(row["href"]).to eq(move_item_path(move, item, from: "find_list"))
    end
  end
end
