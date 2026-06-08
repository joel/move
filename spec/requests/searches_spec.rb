require "rails_helper"

RSpec.describe "Searches" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
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

      get move_search_path(move, q: "skillet")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cast iron skillet").and include("Box 1").and include("Kitchen")
    end

    it "shows the no-results state for an unmatched query" do
      get move_search_path(move, q: "zzzznotathing")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("searches.empty.description"))
    end

    it "excludes needs_correction items from results" do
      box = create(:box, move:, number: "2")
      create(:item, move:, box:, name: "Hidden lamp", review_state: "needs_correction")

      get move_search_path(move, q: "lamp")

      expect(response.body).not_to include("Hidden lamp")
    end

    it "links the sidebar Search destination to this move" do
      get move_boxes_path(move)

      expect(response.body).to include(move_search_path(move))
    end
  end
end
