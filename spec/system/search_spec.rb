# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hybrid search" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user, name: "Seattle Relocation") }

  before do
    login_as(user: user)
    stub_current_tenant("acme")
  end

  it "shows the hero + example hints, then finds an item with its box/room context" do
    room = create(:room, move:, name: "Kitchen")
    box = create(:box, move:, number: "1", room:)
    media = create(:media, move:, box:)
    item = create(:item, :confirmed, move:, box:, source_media: media, name: "Cast iron skillet")
    # Indexing is event-driven off item actions; index the factory item directly.
    Search::RefreshDocument.new.call(item: item)

    visit move_search_path(move)
    expect(page).to have_text(I18n.t("searches.hint"))
    expect(page).to have_text("kitchen electronics")

    fill_in "q", with: "skillet"
    # rack_test submits the GET form on Enter via the submit path; navigate directly.
    visit move_search_path(move, q: "skillet")

    expect(page).to have_text("Cast iron skillet")
    expect(page).to have_text("Box 1").and have_text("Kitchen")
    expect(page).to have_text(I18n.t("searches.match.exact"))
    expect(page).to have_css('img[alt="Cast iron skillet"]')
  end

  it "re-seeds the search from a result card's more-like-this overlay (#724)" do
    box = create(:box, move:, number: "1")
    item = create(:item, :confirmed, move:, box:, name: "Cast iron skillet")
    Search::RefreshDocument.new.call(item: item)

    visit move_search_path(move, q: "skillet")

    # Located by attribute — Capybara's aria-label matching is off by default.
    find("a[aria-label='#{I18n.t("searches.more_like_this", name: "Cast iron skillet")}']").click
    expect(page).to have_css("input[name='q'][value='Cast iron skillet']")
    expect(page).to have_text("Cast iron skillet")
  end

  it "shows the no-results state for an unmatched query" do
    visit move_search_path(move, q: "zzzznotathing")
    expect(page).to have_text(I18n.t("searches.empty.description"))
  end

  it "reaches search from the sidebar nav" do
    create(:box, move:, number: "1")
    visit move_boxes_path(move)
    expect(page).to have_link(href: move_search_path(move))
  end
end
