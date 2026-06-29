# frozen_string_literal: true

require "rails_helper"

RSpec.describe Items::ImageBroadcastSubscriber do
  let(:move) { create(:move, image_provider: "fake") }
  let(:box) { create(:box, move:) }
  let(:item) { create(:item, :manual, move:, box:, name: "Lamp") }

  # Capture the broadcast HTML instead of asserting on the cable.
  def broadcast_html(name)
    captured = {}
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to) { |*_, **kw| captured = kw }
    described_class.new.emit({ name: name, payload: { item_id: item.id } })
    captured[:html].to_s
  end

  it "broadcasts a retryable (editable) failed card so a transient error recovers in place" do
    html = broadcast_html("item.image_generation_failed")

    aggregate_failures do
      expect(html).to include(Components::Boxes::ItemCard.dom_id(item))
      expect(html).to include("try again") # the failed note (apostrophe is HTML-escaped by Phlex)
      expect(html).to include(I18n.t("boxes.contents.generate")) # the retry button
    end
  end

  it "broadcasts a button-less card on success (the image card needs no affordance)" do
    item.update!(source_media: create(:media, move:, box:))

    html = broadcast_html("item.image_generated")

    expect(html).not_to include(I18n.t("boxes.contents.generate"))
  end

  it "ignores unrelated events" do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    described_class.new.emit({ name: "item.updated", payload: { item_id: item.id } })
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
  end
end
