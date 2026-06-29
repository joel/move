require "rails_helper"

RSpec.describe "Galleries" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/gallery" do
    it "renders the gallery hero and grid with box + room context" do
      kitchen = create(:room, move:, name: "Kitchen")
      box = create(:box, move:, number: "3", room: kitchen)
      create(:media, move:, box:)

      get move_gallery_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("galleries.index.subtitle"))
      expect(response.body).to include("Box 3").and include("Kitchen")
    end

    it "orders photos most-recent first by default and reverses for sort=oldest" do
      older_box = create(:box, move:, number: "1")
      newer_box = create(:box, move:, number: "2")
      create(:media, move:, box: older_box, captured_at: 5.days.ago)
      create(:media, move:, box: newer_box, captured_at: 1.hour.ago)

      get move_gallery_path(move)
      expect(response.body.index("Box 2")).to be < response.body.index("Box 1")

      get move_gallery_path(move, sort: "oldest")
      expect(response).to have_http_status(:ok)
      expect(response.body.index("Box 1")).to be < response.body.index("Box 2")
    end

    it "filters to a single room and keeps the sort bookmarkable" do
      kitchen = create(:room, move:, name: "Kitchen")
      garage = create(:room, move:, name: "Garage")
      k_box = create(:box, move:, number: "1", room: kitchen)
      g_box = create(:box, move:, number: "2", room: garage)
      create(:media, move:, box: k_box)
      create(:media, move:, box: g_box)

      get move_gallery_path(move, room_id: kitchen.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Box 1")
      expect(response.body).not_to include("Box 2")
    end

    it "renders the lightbox dialog and tiles that open it with a box link" do
      box = create(:box, move:, number: "7")
      create(:media, move:, box:)

      get move_gallery_path(move)

      aggregate_failures do
        expect(response.body).to include("ha-lightbox")
        expect(response.body).to include("lightbox#open")
        expect(response.body).to include(move_box_path(move, box))
        expect(response.body).to include(I18n.t("galleries.index.lightbox.view_box"))
      end
    end

    it "offers a room as a filter chip only when it has at least one photo" do
      kitchen = create(:room, move:, name: "Kitchen")
      create(:room, move:, name: "EmptyAttic")
      create(:media, move:, box: create(:box, move:, number: "1", room: kitchen))

      get move_gallery_path(move)

      expect(response.body).to include("Kitchen")
      expect(response.body).not_to include("EmptyAttic")
    end

    it "shows AI-generated photos with the Generated badge" do
      box = create(:box, move:, number: "1")
      create(:media, move:, box:, captured_via: "generated")

      get move_gallery_path(move)

      expect(response.body).to include(I18n.t("galleries.index.generated"))
    end

    it "excludes photos whose box has been discarded" do
      box = create(:box, move:, number: "9")
      create(:media, move:, box:)
      box.discard

      get move_gallery_path(move)

      expect(response.body).not_to include("Box 9")
    end

    it "surfaces the cap notice when the photo count exceeds the cap" do
      stub_const("GalleriesController::CAP", 1)
      box = create(:box, move:, number: "1")
      create_list(:media, 2, move:, box:)

      get move_gallery_path(move)
      expect(response.body).to include(I18n.t("galleries.index.capped.recent", count: 1))

      get move_gallery_path(move, sort: "oldest")
      expect(response.body).to include(I18n.t("galleries.index.capped.oldest", count: 1))
    end

    it "takes the oldest photos (not a reversed newest window) when capped + sort=oldest" do
      stub_const("GalleriesController::CAP", 1)
      create(:media, move:, box: create(:box, move:, number: "1"), captured_at: 10.days.ago)
      create(:media, move:, box: create(:box, move:, number: "2"), captured_at: 1.hour.ago)

      get move_gallery_path(move, sort: "oldest")

      # The single capped tile is the genuinely-oldest photo (Box 1), not the
      # newest one reversed into view.
      expect(response.body).to include("Box 1")
      expect(response.body).not_to include("Box 2")
    end

    it "renders the empty state when the move has no photos" do
      get move_gallery_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("galleries.index.empty.title"))
    end

    it "renders a room-specific empty state with a clear-filter action" do
      room = create(:room, move:, name: "Attic")

      get move_gallery_path(move, room_id: room.id)

      expect(response.body).to include(I18n.t("galleries.index.empty.filtered_title"))
      expect(response.body).to include(I18n.t("galleries.index.filters.clear"))
    end

    it "404s for a user who is not a member of the move" do
      other = create(:user)
      stub_current_user(other)

      get move_gallery_path(move)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /moves/:move_id/menu" do
    it "links the Gallery from the Menu hub" do
      get move_menu_path(move)

      expect(response.body).to include(move_gallery_path(move))
      expect(response.body).to include(I18n.t("menu.show.gallery"))
    end
  end
end
