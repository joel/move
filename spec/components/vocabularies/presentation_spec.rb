# frozen_string_literal: true

require "rails_helper"

# #472: the icon + chip tint per vocabulary kind moved off Vocabulary (the
# vocabularies pack's public data contract) into the component layer. These
# examples pin the mapping and the markup it drives so the move stays a pure
# refactor: the row medallion and the empty state render the same icon and tint.
RSpec.describe Components::Vocabularies::Presentation do
  let(:rooms) { Vocabulary.find("rooms") }
  let(:boxes_icon) { Components::Icons::Boxes.new(css: "h-6 w-6").call }

  def render_component(component)
    ApplicationController.render(component, layout: false)
  end

  it "maps rooms to the sage room chip and the boxes icon" do
    expect(described_class.chip_kind(rooms)).to eq(:room)
    expect(described_class.icon(rooms)).to eq(Components::Icons::Boxes)
  end

  it "has a style for every managed vocabulary kind" do
    Vocabulary::KINDS.each do |kind|
      vocabulary = Vocabulary.find(kind)
      expect(Components::Ui::Chip::KINDS).to have_key(described_class.chip_kind(vocabulary))
      expect(described_class.icon(vocabulary)).to be < Components::Icons::Base
    end
  end

  it "keeps presentation off the public Vocabulary contract" do
    expect(rooms).not_to respond_to(:icon)
    expect(rooms).not_to respond_to(:chip_kind)
  end

  describe "rendered markup" do
    let(:move) { create(:move) }

    it "tints the row medallion sage and renders the boxes icon in it" do
      room = create(:room, move:, name: "Kitchen")
      html = render_component(
        Components::Vocabularies::Row.new(move:, vocabulary: rooms, record: room,
                                          usage_count: 1, can_edit: true)
      )

      medallion = Nokogiri::HTML5.fragment(html).at_css("div.h-12.w-12.rounded-full")
      expect(medallion["class"]).to end_with(" bg-accent-sage/15 text-accent-sage")
      expect(medallion.inner_html).to eq(boxes_icon)
    end

    it "renders the boxes icon in the empty state" do
      html = render_component(
        Components::Vocabularies::List.new(move:, vocabulary: rooms, records: [],
                                           usage_counts: {}, can_edit: true)
      )

      expect(html).to include(I18n.t("vocabularies.rooms.empty_title"))
      expect(html).to include(Components::Icons::Boxes.new(css: "h-7 w-7").call)
    end
  end
end
