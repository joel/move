# frozen_string_literal: true

require "rails_helper"

# #1007 — Box#padded_number ("007") is the one name for a box (#696): the label
# printed on the physical box, the box header, the PDFs. Every surface where a
# person matches the screen against a physical box must use the same name.
RSpec.describe "Box padded labels on lookup surfaces (#1007)" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:room) { create(:room, move:, name: "Kitchen") }
  let(:box) { create(:box, move:, number: "7", room:) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  def pending_photo(target = box)
    media = create(:media, move:, box: target)
    create(:item, move:, box: target, source_media: media, name: "Lamp", review_state: "pending_review")
    media
  end

  it "names the box 007 on a search result location" do
    create(:item, :confirmed, move:, box:, name: "Cast iron skillet")
    move.items.includes(box: :room).find_each { |i| Search::RefreshDocument.new.call(item: i) }

    get move_search_path(move, q: "skillet")

    expect(response.body).to include("Box 007 · Kitchen")
  end

  it "names the box 007 on the find-list group header" do
    create(:find_list_entry, move:, user:, item: create(:item, move:, box:, name: "Charger"))

    get move_find_list_path(move)

    expect(response.body).to include("Box 007 · Kitchen")
  end

  it "names the box 007 on the review queue card caption" do
    pending_photo

    get move_review_path(move)

    expect(response.body).to include("Box 007 · Kitchen")
  end

  it "names the box 007 on the queue-mode photo review badge and view-box label" do
    media = pending_photo

    get move_box_review_photo_path(move, box, media, queue: "move")

    aggregate_failures do
      expect(response.body).to include(%(aria-label="#{I18n.t("reviews.photo.view_box", number: "007")}"))
      expect(response.body).to include(I18n.t("reviews.photo.queue_badge", number: "007"))
    end
  end

  it "names move-to-box targets by padded label, keeping string-distinct numbers unique" do
    media = pending_photo
    create(:box, move:, number: "1")
    create(:box, move:, number: "01")
    create(:box, move:, number: "12", status: "unpacked")

    get move_box_review_photo_path(move, box, media)

    texts = response.parsed_body.css("select[name=target_box_id] option").map(&:text)
    aggregate_failures do
      expect(texts).to include(I18n.t("reviews.photo.move_to_box", number: "1"))
        .and include(I18n.t("reviews.photo.move_to_box", number: "01"))
      expect(texts).to include(I18n.t("reviews.photo.move_to_box_unpacked", number: "012"))
      expect(texts.uniq.size).to eq(texts.size)
    end
  end

  it "names move-to-box targets 007 when the number is unambiguous" do
    other = create(:box, move:, number: "3")
    media = pending_photo(other)
    box # the target

    get move_box_review_photo_path(move, other, media)

    texts = response.parsed_body.css("select[name=target_box_id] option").map(&:text)
    expect(texts).to include(I18n.t("reviews.photo.move_to_box", number: "007"))
  end

  it "names the box 007 on the gallery tile caption" do
    create(:media, move:, box:)

    get move_gallery_path(move)

    expect(response.body).to include("Box 007 · Kitchen")
  end

  it "names the box 007 on the gallery group member row" do
    create(:item, :auto_confirmed, move:, box:, name: "AA battery")
    create(:item, :auto_confirmed, move:, box: create(:box, move:, number: "10"), name: "AAA battery")
    Clusters::Recompute.new.call(move:)

    get move_gallery_group_path(move, move.item_clusters.sole)

    expect(response.body).to include("Box 007 · Kitchen").and include("Box 010")
  end

  it "names the boxes 007 and 010 on the gallery Groups card chips" do
    create(:item, :auto_confirmed, move:, box:, name: "AA battery")
    create(:item, :auto_confirmed, move:, box: create(:box, move:, number: "10"), name: "AAA battery")
    Clusters::Recompute.new.call(move:)

    get move_gallery_path(move, view: "groups")

    chips = I18n.t("galleries.groups.card.box_chip", number: "007")
    expect(response.body).to include(chips).and include("Box 010")
  end

  it "names the box 007 on the boxes-grid card badge" do
    box

    get move_boxes_path(move)

    expect(response.body).to include(I18n.t("boxes.card.badge", number: "007"))
  end
end
