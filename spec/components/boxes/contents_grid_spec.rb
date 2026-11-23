# frozen_string_literal: true

require "rails_helper"

# The contents grid's standalone region (#889): the departed-photo stream
# redraws it, so it must always exist inside the grid and hold exactly the
# standalone cards, newest first. Exercised through the box-detail page (full
# view context), like the other button_to-bearing box components.
RSpec.describe "Box detail — contents grid standalone region", type: :request do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:region_id) { Components::Boxes::ContentsGrid::STANDALONE_ID }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  def region(html) = Nokogiri::HTML(html).at_css(".grid > ##{region_id}.contents")

  it "holds the standalone cards newest first, after the photo cards" do
    box = create(:box, :with_room, move:)
    photo = create(:media, move:, box:)
    create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates")
    lamp = create(:item, :manual, move:, box:, name: "Lamp", created_at: 2.hours.ago)
    vase = create(:item, :manual, move:, box:, name: "Vase", created_at: 1.hour.ago)

    get move_box_path(move, box)

    ids = region(response.body).css("[id]").pluck("id").grep(/\Abox_item_.+_card\z/)
    expect(ids).to eq([vase, lamp].map { |item| Components::Boxes::ItemCard.dom_id(item) })
    expect(region(response.body).at_css("##{Components::Boxes::PhotoCard.dom_id(photo)}")).to be_nil
  end

  it "renders the region even when the grid has no standalone cards" do
    box = create(:box, :with_room, move:)
    photo = create(:media, move:, box:)
    create(:item, :confirmed, move:, box:, source_media: photo, name: "Plates")

    get move_box_path(move, box)

    expect(region(response.body)).to be_present
    expect(region(response.body).element_children).to be_empty
  end
end
