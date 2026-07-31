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

  # #735 — the in-place loop: mark found (phase bypass — the box is sealed),
  # restore via the same stable-id toggle, then unpin through the swipe-layer
  # form (rack_test ignores the lg: CSS split, so every control is clickable).
  it "marks an item found from the list, restores it, and unpins via the swipe control" do
    box = create(:box, move:, number: "12", status: "sealed")
    item = create(:item, :manual, move:, box:, name: "Bath Towels")
    create(:find_list_entry, move:, user:, item:)

    visit move_find_list_path(move)
    find("#find-list-row-found-#{item.id}").click

    expect(page).to have_text(I18n.t("find_lists.show.found_count", found: 1, total: 1))
    # #738: retrieving from the sealed box opened it for unpacking — and said so.
    expect(page).to have_text(I18n.t("find_lists.flash.box_opened", number: "12"))
    expect(box.reload.status).to eq("unpacking")

    find("#find-list-row-found-#{item.id}").click # the same stable id now restores

    expect(item.reload.presence_state).to eq("in_box")
    # Restore never auto-reverts the box (reopen semantics — a user call).
    expect(box.reload.status).to eq("unpacking")

    find("#find-list-swipe-unpin-#{item.id}").click

    expect(page).to have_text(I18n.t("find_lists.show.empty.title"))
  end

  # #747 — pinning while browsing a closed box's contents: the photo card's
  # chip and the standalone card's icon overlay both drive the same toggle.
  it "pins and unpins from a sealed box's contents grid" do
    box = create(:box, move:, number: "9", status: "sealed")
    photo = create(:media, move:, box:)
    create(:item, move:, box:, source_media: photo, name: "Plates")
    lamp = create(:item, :manual, move:, box:, name: "Desk Lamp")

    visit move_box_path(move, box)
    find("#find-list-toggle-chip-btn-#{box.items.find_by!(name: "Plates").id}").click

    # No-JS fallback lands on the list with the pin present.
    expect(page).to have_text(I18n.t("find_lists.show.title"))
    expect(page).to have_text("Plates")

    visit move_box_path(move, box)
    find("#find-list-toggle-btn-#{lamp.id}").click
    expect(FindListEntry.where(move:, user_id: user.id).count).to eq(2)

    # The same controls unpin: chip and icon both render the pinned state.
    visit move_box_path(move, box)
    find("#find-list-toggle-btn-#{lamp.id}").click
    expect(FindListEntry.where(move:, user_id: user.id, item: lamp)).to be_empty
  end

  # #749 — the review walk lists a photo's items in full, so a closed box's
  # rows carry the same pin toggle as the contents grid.
  it "pins from a sealed box's review screen" do
    box = create(:box, move:, number: "4", status: "sealed")
    photo = create(:media, move:, box:)
    item = create(:item, move:, box:, source_media: photo, name: "Blender",
                         review_state: "pending_review")

    visit move_box_review_photo_path(move, box, photo)
    find("#find-list-toggle-btn-#{item.id}").click

    # No-JS fallback lands on the list with the pin present.
    expect(page).to have_text(I18n.t("find_lists.show.title"))
    expect(FindListEntry.where(move:, user_id: user.id, item:)).to exist
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
