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

    it "emits real slide dimensions scaled into the detail box when edge transforms serve (#675)" do
      original_host = Rails.application.config.x.media_transform_host
      original_secret = Rails.application.config.x.media_transform_secret
      Rails.application.config.x.media_transform_host = "media.example.org"
      Rails.application.config.x.media_transform_secret = "s3cr3t"
      box = create(:box, move:, number: "4")
      media = create(:media, move:, box:)
      media.image.blob.update!(
        metadata: media.image.blob.metadata.merge("width" => 2048, "height" => 1024)
      )

      get move_gallery_path(move)

      # 2048x1024 scaled into the 1600 box -> 1600x800 (scale-down, never up).
      expect(response.body).to include('data-pswp-width="1600"')
      expect(response.body).to include('data-pswp-height="800"')
    ensure
      Rails.application.config.x.media_transform_host = original_host
      Rails.application.config.x.media_transform_secret = original_secret
    end

    it "emits the raw master dimensions when the fallback proxies the unresized master (#676)" do
      box = create(:box, move:, number: "4")
      media = create(:media, move:, box:)
      media.image.blob.update!(
        metadata: media.image.blob.metadata.merge("width" => 2048, "height" => 1024)
      )

      get move_gallery_path(move)

      # No edge host (dev/test): the served detail IS the 2048x1024 master.
      expect(response.body).to include('data-pswp-width="2048"')
      expect(response.body).to include('data-pswp-height="1024"')
    end

    it "omits slide dimensions while the blob is unanalyzed (JS falls back to its estimate)" do
      box = create(:box, move:, number: "4")
      media = create(:media, move:, box:)
      media.image.blob.update!(metadata: {})

      get move_gallery_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("data-pswp-width")
    end

    it "paints the blur-up preview under a tile when the blob carries an lqip (#681)" do
      box = create(:box, move:, number: "4")
      media = create(:media, move:, box:)
      media.image.blob.update!(
        metadata: media.image.blob.metadata.merge("lqip" => "dGVzdA==")
      )

      get move_gallery_path(move)

      expect(response.body).to include("background-image: url(data:image/jpeg;base64,dGVzdA==)")
    end

    it "drops a non-base64 or non-string lqip instead of reaching the style attribute" do
      box = create(:box, move:, number: "4")
      injection = create(:media, move:, box:, captured_at: 1.hour.ago)
      injection.image.blob.update!(
        metadata: injection.image.blob.metadata.merge("lqip" => "aa) no-repeat; background:url(//evil\n")
      )
      corrupt = create(:media, move:, box:, captured_at: 2.hours.ago)
      corrupt.image.blob.update!(metadata: corrupt.image.blob.metadata.merge("lqip" => true))

      get move_gallery_path(move)

      expect(response).to have_http_status(:ok) # non-String must degrade, not 500
      expect(response.body).not_to include("background-image")
      expect(response.body).not_to include("evil")
    end

    it "renders no preview layer while the blob has no lqip (legacy) — plain placeholder" do
      box = create(:box, move:, number: "4")
      create(:media, move:, box:)

      get move_gallery_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("background-image: url(data:")
    end

    it "renders the lightbox controller and tiles that open it with a box link" do
      box = create(:box, move:, number: "7")
      create(:media, move:, box:)

      get move_gallery_path(move)

      aggregate_failures do
        expect(response.body).to include('data-controller="lightbox"')
        expect(response.body).to include("lightbox#open")
        expect(response.body).to include(move_box_path(move, box))
        expect(response.body).to include(I18n.t("galleries.index.lightbox.view_box"))
      end
    end

    it "seeds the PhotoSwipe wrapper with thumb-first tile data and chrome labels" do
      box = create(:box, move:, number: "7")
      create(:media, move:, box:)

      get move_gallery_path(move)

      aggregate_failures do
        # Tiles carry both srcs — msrc (thumb, grid-cached) + src (detail). In
        # test both resolve to the proxied master, so assert presence, not
        # distinctness.
        expect(response.body).to include("data-thumb=")
        expect(response.body).to include("data-src=")
        # PhotoSwipe's chrome labels ride a Stimulus Object value.
        expect(response.body).to include("data-lightbox-labels-value=")
        expect(response.body).to include(I18n.t("galleries.index.lightbox.prev"))
        # Turbo must never snapshot PhotoSwipe's body-appended DOM.
        expect(response.body).to include("turbo:before-cache@document->lightbox#teardown")
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

  describe "GET /moves/:move_id/gallery?view=groups (#633)" do
    let(:box_two) { create(:box, move:, number: "2") }
    let(:box_ten) { create(:box, move:, number: "10") }

    it "renders family cards with counts, box chips and a member photo, widest spread first" do
      photo = create(:media, move:, box: box_two, status: "ready")
      create(:item, :auto_confirmed, move:, box: box_two, name: "AA battery", source_media: photo)
      create(:item, :auto_confirmed, move:, box: box_ten, name: "AAA battery")
      Clusters::Recompute.new.call(move:)

      get move_gallery_path(move, view: "groups")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("galleries.groups.subtitle"))
      expect(response.body).to include("2 items").and include("2 boxes")
      expect(response.body).to include("Box 2").and include("Box 10")
      expect(response.body).to include(move_gallery_group_path(move, move.item_clusters.sole))
      # The member photo resolves through the root gallery layer into the quilt.
      expect(response.body).to include("<img")
    end

    it "shows the no-items state without requesting a refresh" do
      get move_gallery_path(move, view: "groups")

      expect(response.body).to include(I18n.t("galleries.groups.no_items.title"))
      expect(ClusterState.where(move_id: move.id)).to be_empty
    end

    it "shows the organizing state and lazily claims the first refresh, idempotently" do
      create(:item, :auto_confirmed, move:, box: box_two, name: "AA battery")
      configured = instance_double(ActiveJob::ConfiguredJob, perform_later: nil)
      allow(Clusters::RefreshJob).to receive(:set).and_return(configured)

      2.times { get move_gallery_path(move, view: "groups") }

      expect(response.body).to include(I18n.t("galleries.groups.organizing.title"))
      expect(configured).to have_received(:perform_later).once # claim held across GETs
    end

    it "shows the explanatory empty state when computed but nothing grouped" do
      create(:item, :auto_confirmed, move:, box: box_two, name: "Wine decanter")
      Clusters::Recompute.new.call(move:)

      get move_gallery_path(move, view: "groups")

      expect(response.body).to include(I18n.t("galleries.groups.none.title"))
    end

    it "treats an unknown view as photos (whitelist)" do
      get move_gallery_path(move, view: "evil")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("galleries.index.subtitle"))
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
