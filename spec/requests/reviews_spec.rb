# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Per-photo review" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  def detected(name:, **attrs)
    create(:item, move:, box:, source_media: media, name:, review_state: "pending_review", **attrs)
  end

  describe "GET .../review (entry)" do
    it "enters the walk at the first photo with items" do
      detected(name: "Lamp")

      get move_box_review_path(move, box)

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
    end

    it "redirects back to the box when there is nothing to review" do
      get move_box_review_path(move, box)

      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:notice]).to eq(I18n.t("reviews.flash.nothing"))
    end
  end

  describe "GET .../review/photo/:media_id" do
    it "lists every item from the photo with progress" do
      detected(name: "Coffee machine")
      detected(name: "Fruit bowl")

      get move_box_review_photo_path(move, box, media)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Coffee machine").and include("Fruit bowl")
      expect(response.body).to include(I18n.t("reviews.photo.progress", position: 1, total: 1))
    end

    it "marks the photo's unreviewed items confirmed when shown" do
      pending_item = detected(name: "Chair")
      needs = detected(name: "Desk", review_state: "needs_correction")

      get move_box_review_photo_path(move, box, media)

      expect(pending_item.reload.review_state).to eq("confirmed")
      expect(needs.reload.review_state).to eq("confirmed")
    end

    it "links to the next photo when more remain" do
      detected(name: "Lamp")
      other = create(:media, move:, box:)
      create(:item, move:, box:, source_media: other, name: "Sofa", review_state: "pending_review")

      get move_box_review_photo_path(move, box, media)

      expect(response.body).to include(move_box_review_photo_path(move, box, other))
      expect(response.body).to include(I18n.t("reviews.photo.next"))
    end
  end

  describe "PATCH .../rename" do
    it "renames the item and answers 204 (no navigation)" do
      item = detected(name: "Cofee machine")

      patch move_box_review_rename_item_path(move, box, media, item), params: { name: "Coffee machine" }

      expect(response).to have_http_status(:no_content)
      expect(item.reload.name).to eq("Coffee machine")
    end
  end

  describe "PATCH .../remove" do
    it "removes the item from the box and returns to the photo" do
      item = detected(name: "Glass backsplash")

      patch move_box_review_remove_item_path(move, box, media, item)

      expect(item.reload.presence_state).to eq("removed")
      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
    end
  end

  describe "POST .../items (add a missed item)" do
    it "creates a confirmed manual item tied to the photo" do
      expect do
        post move_box_review_add_item_path(move, box, media), params: { item: { name: "Kettle" } }
      end.to change(box.items, :count).by(1)

      item = box.items.find_by(name: "Kettle")
      expect(item).to have_attributes(created_via: "manual", review_state: "confirmed", source_media_id: media.id)
      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
    end

    it "re-shows the photo with an alert when the name is blank" do
      post move_box_review_add_item_path(move, box, media), params: { item: { name: "" } }

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
      expect(flash[:alert]).to eq(I18n.t("reviews.flash.add_failed"))
    end
  end

  describe "archived Move (read-only)" do
    let(:move) { create(:move, :archived, created_by: user) }

    it "shows the photo read-only without confirming items" do
      item = detected(name: "Lamp")

      get move_box_review_photo_path(move, box, media)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("reviews.photo.view_only"))
      expect(item.reload.review_state).to eq("pending_review")
    end

    it "refuses a rename and redirects with the archived alert" do
      item = detected(name: "Lamp")

      patch move_box_review_rename_item_path(move, box, media, item), params: { name: "Desk lamp" }

      expect(item.reload.name).to eq("Lamp")
      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:alert]).to eq(I18n.t("moves.archived_alert"))
    end
  end
end
