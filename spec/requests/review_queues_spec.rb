# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ReviewQueues" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  def pending_photo(box:, captured_at: Time.current, items: 1)
    media = create(:media, move:, box:, captured_at:)
    create_list(:item, items, move:, box:, source_media: media, review_state: "pending_review")
    media
  end

  describe "GET /moves/:move_id/review" do
    it "renders pending photos with box + room context and a pending-item count badge" do
      kitchen = create(:room, move:, name: "Kitchen")
      box = create(:box, move:, number: "3", room: kitchen)
      pending_photo(box:, items: 2)

      get move_review_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("review_queues.show.subtitle"))
      expect(response.body).to include("Box 3").and include("Kitchen")
      expect(response.body).to include(I18n.t("review_queues.show.pending_badge", count: 2))
    end

    it "orders photos oldest-first across boxes (FIFO)" do
      pending_photo(box: create(:box, move:, number: "1"), captured_at: 1.hour.ago)
      pending_photo(box: create(:box, move:, number: "2"), captured_at: 5.days.ago)

      get move_review_path(move)

      expect(response.body.index("Box 2")).to be < response.body.index("Box 1")
    end

    it "links Review all and every tile into the queue-mode walk with prefetch disabled" do
      box = create(:box, move:, number: "1")
      media = pending_photo(box:)

      get move_review_path(move)

      href = move_box_review_photo_path(move, box, media, queue: "move")
      aggregate_failures do
        expect(response.body).to include(I18n.t("review_queues.show.review_all"))
        expect(response.body).to include(href)
        # Opening a review photo confirms its items — hover-prefetch must be off.
        expect(response.body).to include('data-turbo-prefetch="false"')
      end
    end

    it "renders the three-way toggle with To review active, and the pill on the gallery too" do
      get move_review_path(move)
      expect(response.body).to include(I18n.t("galleries.toggle.to_review"))
        .and include(I18n.t("galleries.toggle.photos"))
        .and include(I18n.t("galleries.toggle.groups"))

      get move_gallery_path(move)
      expect(response.body).to include(move_review_path(move))
    end

    it "shows the caught-up empty state once every item on a reviewable photo is confirmed" do
      box = create(:box, move:, number: "1")
      media = create(:media, move:, box:)
      create(:item, :confirmed, move:, box:, source_media: media)

      get move_review_path(move)

      expect(response.body).to include(I18n.t("review_queues.show.empty.caught_up_title"))
      expect(response.body).to include(move_gallery_path(move))
    end

    it "shows the nothing-to-review empty state when no photo ever produced an item" do
      get move_review_path(move)

      expect(response.body).to include(I18n.t("review_queues.show.empty.title"))
    end

    it "keeps the OLDEST photos when capped and says so" do
      stub_const("ReviewQueuesController::CAP", 1)
      pending_photo(box: create(:box, move:, number: "1"), captured_at: 10.days.ago)
      pending_photo(box: create(:box, move:, number: "2"), captured_at: 1.hour.ago)

      get move_review_path(move)

      aggregate_failures do
        expect(response.body).to include(I18n.t("review_queues.show.capped", count: 1))
        expect(response.body).to include("Box 1")
        expect(response.body).not_to include("Box 2")
      end
    end

    it "excludes a photo whose only pending item now lives in another box (co-location)" do
      box = create(:box, move:, number: "1")
      media = create(:media, move:, box:)
      create(:item, move:, box: create(:box, move:, number: "2"), source_media: media,
                    review_state: "pending_review")

      get move_review_path(move)

      # Opening that photo would confirm nothing, so it must not queue.
      expect(response.body).not_to include(I18n.t("review_queues.show.review_all"))
    end

    it "404s for a move outside the member's scope" do
      foreign = create(:move, created_by: create(:user), name: "Foreign")

      get move_review_path(foreign)

      expect(response).to have_http_status(:not_found)
    end
  end
end
