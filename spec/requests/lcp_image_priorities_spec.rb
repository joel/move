# frozen_string_literal: true

require "rails_helper"

# #673: LCP hygiene. Hero detail images are the page's largest paint — they must
# never be lazy (that deprioritizes the most important pixel) and carry
# fetchpriority=high. Grids eager-load only the above-the-fold first row
# (EAGER_TILES = 4) and mark every tile decoding=async.
RSpec.describe "LCP image priorities" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "gallery grid" do
    it "eager-loads the first EAGER_TILES tiles, lazy-loads the rest, decodes async" do
      6.times { |i| create(:media, move:, box:, captured_at: i.hours.ago) }

      get move_gallery_path(move)

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body.scan('loading="eager"').size).to eq(4)
        expect(response.body.scan('loading="lazy"').size).to eq(2)
        expect(response.body.scan('decoding="async"').size).to eq(6)
      end
    end
  end

  describe "box contents grid" do
    it "eager-loads the first row of photo cards, lazy-loads the rest" do
      5.times { |i| create(:media, move:, box:, captured_at: i.hours.ago) }

      get move_box_path(move, box)

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body.scan('loading="eager"').size).to eq(4)
        expect(response.body.scan('loading="lazy"').size).to eq(1)
      end
    end

    it "continues the eager window into image-backed standalone item cards (#673 Codex)" do
      # One gallery photo + generated-image items: the items are "standalone"
      # (ItemCard with its own thumbnail), and with < EAGER_TILES photos they
      # fill the first visible row — they must not lazy-load.
      create(:media, move:, box:)
      4.times do |i|
        generated = create(:media, move:, box:, captured_via: "generated")
        create(:item, move:, box:, source_media: generated, name: "Gen #{i}")
      end

      get move_box_path(move, box)

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        # photo (index 0) + first 3 item cards (indices 1-3) eager; 4th card lazy.
        expect(response.body.scan('loading="eager"').size).to eq(4)
        expect(response.body.scan('loading="lazy"').size).to eq(1)
      end
    end
  end

  describe "review queue grid" do
    it "eager-loads the first row of pending photos, lazy-loads the rest" do
      5.times do |i|
        photo = create(:media, move:, box:, captured_at: i.hours.ago)
        create(:item, move:, box:, source_media: photo, name: "Item #{i}", review_state: "pending_review")
      end

      get move_review_path(move)

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body.scan('loading="eager"').size).to eq(4)
        expect(response.body.scan('loading="lazy"').size).to eq(1)
      end
    end
  end

  describe "hero detail images (the page's LCP element)" do
    it "item detail: high priority, async decode, never lazy" do
      media = create(:media, move:, box:)
      item = create(:item, move:, box:, source_media: media, name: "Lamp")

      get move_item_path(move, item)

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include('fetchpriority="high"')
        expect(response.body).to include('decoding="async"')
        expect(response.body).not_to include('loading="lazy"')
      end
    end

    it "review photo: high priority, never lazy" do
      media = create(:media, move:, box:)
      create(:item, move:, box:, source_media: media, name: "Lamp", review_state: "pending_review")

      get move_box_review_photo_path(move, box, media)

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include('fetchpriority="high"')
        expect(response.body).not_to include('loading="lazy"')
      end
    end

    it "recovery photo: high priority, never lazy" do
      media = create(:media, move:, box:)
      create(:recognition_run, :failed, move:, box:, media:, error_message: "boom")

      get move_box_recovery_photo_path(move, box, media)

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include('fetchpriority="high"')
        expect(response.body).not_to include('loading="lazy"')
      end
    end
  end
end
