# frozen_string_literal: true

require "rails_helper"

# The full #730 loop on the no-JS surface: pin from search, walk the
# box-grouped list, watch an unpacked item strike, clear it.
RSpec.describe "Find list flow" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  it "pins from search, groups by box, strikes on unpack, and clears found" do
    room = create(:room, move:, name: "Kitchen")
    box = create(:box, move:, number: "3", room:, status: "unpacking")
    item = create(:item, :confirmed, move:, box:, name: "Cast iron skillet")
    Search::RefreshDocument.new.call(item: item)

    visit move_search_path(move, q: "skillet")
    find("button[aria-label='#{I18n.t("find_lists.toggle.add", name: "Cast iron skillet")}']").click

    # No-JS fallback lands on the list; a fresh search visit shows the pill.
    expect(page).to have_text(I18n.t("find_lists.show.title"))
    visit move_search_path(move)
    expect(page).to have_text(I18n.t("find_lists.search_link", count: 1))
    click_link I18n.t("find_lists.search_link", count: 1)
    expect(page).to have_text("#{I18n.t("find_lists.show.box_label", number: "3")} · Kitchen")

    Items::MarkRemoved.new.call(item: item, actor: user)
    visit move_find_list_path(move)

    expect(page).to have_text(I18n.t("find_lists.show.found"))
    expect(page).to have_text(I18n.t("find_lists.show.found_count", found: 1, total: 1))

    click_button I18n.t("find_lists.show.clear_found")

    expect(page).to have_text(I18n.t("find_lists.show.empty.title"))
  end

  it "pins and unpins from the item detail page" do
    box = create(:box, move:, number: "5")
    item = create(:item, :manual, move:, box:, name: "Desk Lamp")

    visit move_item_path(move, item)
    click_button I18n.t("find_lists.toggle.add_short")

    expect(FindListEntry.where(move:, user_id: user.id, item:)).to exist

    visit move_item_path(move, item)
    click_button I18n.t("find_lists.toggle.on_list")

    expect(FindListEntry.where(move:, user_id: user.id, item:)).to be_empty
  end
end
