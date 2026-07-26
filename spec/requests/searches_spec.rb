require "rails_helper"

RSpec.describe "Searches" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  # Indexing is event-driven off the item actions; factory-built items don't emit
  # those events, so index them explicitly for these controller-level specs.
  def index_all
    move.items.includes(box: :room).find_each { |i| Search::RefreshDocument.new.call(item: i) }
  end

  describe "GET /moves/:move_id/search" do
    it "renders the search hero + example hints with no query" do
      get move_search_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("searches.hint"))
      expect(response.body).to include("kitchen electronics")
    end

    it "returns matching items with box + room context" do
      room = create(:room, move:, name: "Kitchen")
      box = create(:box, move:, number: "1", room:)
      create(:item, :confirmed, move:, box:, name: "Cast iron skillet")
      index_all

      get move_search_path(move, q: "skillet")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cast iron skillet").and include("Box 1").and include("Kitchen")
    end

    it "renders the item's photo thumbnail on the result card" do
      box = create(:box, move:, number: "3")
      media = create(:media, move:, box:)
      create(:item, :confirmed, move:, box:, source_media: media, name: "Copper kettle")
      index_all

      get move_search_path(move, q: "kettle")

      expect(response).to have_http_status(:ok)
      aggregate_failures do
        expect(response.body).to include('alt="Copper kettle"')
        expect(response.body).to include('loading="eager"')
      end
    end

    it "renders the placeholder tile, not an image, for a photo-less item" do
      box = create(:box, move:, number: "4")
      create(:item, :confirmed, move:, box:, name: "Bare lamp")
      index_all

      get move_search_path(move, q: "lamp")

      expect(response.body).to include("Bare lamp")
      expect(response.body).not_to include("<img")
    end

    it "eager-loads the first row of thumbnails, lazy-loads the rest" do
      box = create(:box, move:, number: "5")
      4.times do |i|
        media = create(:media, move:, box:)
        create(:item, :confirmed, move:, box:, source_media: media, name: "Mug #{i}")
      end
      index_all

      get move_search_path(move, q: "mug")

      aggregate_failures do
        expect(response.body.scan('loading="eager"').size).to eq(3)
        expect(response.body.scan('loading="lazy"').size).to eq(1)
      end
    end

    it "shows the no-results state for an unmatched query" do
      get move_search_path(move, q: "zzzznotathing")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("searches.empty.description"))
    end

    it "excludes needs_correction items from results" do
      box = create(:box, move:, number: "2")
      create(:item, move:, box:, name: "Hidden lamp", review_state: "needs_correction")
      index_all

      get move_search_path(move, q: "lamp")

      expect(response.body).not_to include("Hidden lamp")
    end

    it "surfaces recent successful searches on the empty state, replacing examples" do
      room = create(:room, move:, name: "Kitchen")
      box = create(:box, move:, number: "1", room:)
      create(:item, :confirmed, move:, box:, name: "Cast iron skillet")
      index_all

      get move_search_path(move, q: "skillet")
      get move_search_path(move)

      expect(response.body).to include(I18n.t("searches.recent"))
      expect(response.body).to include("“skillet”")
      expect(response.body).not_to include("kitchen electronics")
    end

    it "does not remember a search that found nothing" do
      get move_search_path(move, q: "zzzznotathing")
      get move_search_path(move)

      expect(response.body).not_to include(I18n.t("searches.recent"))
      expect(response.body).to include("kitchen electronics")
    end

    it "links the sidebar Search destination to this move" do
      get move_boxes_path(move)

      expect(response.body).to include(move_search_path(move))
    end
  end
end
