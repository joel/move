# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Items" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/boxes/:box_id/items/new" do
    it "renders the manual add form" do
      get new_move_box_item_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("items.new.title"))
      expect(response.body).to include(I18n.t("items.form.name"))
    end
  end

  describe "POST /moves/:move_id/boxes/:box_id/items" do
    it "creates a confirmed manual item and redirects to the box" do
      expect do
        post move_box_items_path(move, box), params: { item: { name: "Lamp", quantity: "2" } }
      end.to change(box.items, :count).by(1)

      item = box.items.last
      expect(item).to have_attributes(name: "Lamp", quantity: 2, created_via: "manual", review_state: "confirmed")
      expect(response).to redirect_to(move_box_path(move, box))
    end

    it "re-renders with errors for a blank name" do
      post move_box_items_path(move, box), params: { item: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("items.new.title"))
    end

    it "assigns selection-only category and tags" do
      category = create(:category, move:, name: "Kitchenware")
      tag = create(:tag, move:, name: "Heavy")

      post move_box_items_path(move, box),
           params: { item: { name: "Plates", category_id: category.id, tag_ids: [tag.id] } }

      item = box.items.last
      expect(item.category).to eq(category)
      expect(item.tags).to contain_exactly(tag)
    end
  end

  describe "GET /moves/:move_id/items/:id" do
    it "renders the detail/edit screen" do
      item = create(:item, :manual, move:, box:, name: "Toaster")

      get move_item_path(move, item)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("items.show.title")).and include("Toaster")
    end
  end

  describe "PATCH /moves/:move_id/items/:id" do
    it "updates editable attributes" do
      item = create(:item, :manual, move:, box:, name: "Old")

      patch move_item_path(move, item), params: { item: { name: "New", quantity: "4" } }

      expect(item.reload).to have_attributes(name: "New", quantity: 4)
      expect(response).to redirect_to(move_item_path(move, item))
    end

    it "re-renders the editable form (not the read-only view) on a validation error" do
      item = create(:item, :manual, move:, box:, name: "Old")

      patch move_item_path(move, item), params: { item: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      # The editor must keep the form to fix the error, not fall into read-only.
      expect(response.body).to include(I18n.t("items.show.save"))
      expect(response.body).not_to include(I18n.t("items.show.view_only"))
    end

    context "when editing was reached via review Correct (review_suggestion_id)" do
      it "resolves the edited suggestion on save and resumes at the next one" do
        editing = create(:recognition_suggestion, :with_item, move:, box:, state: "pending", confidence_score: 0.5)
        nxt = create(:recognition_suggestion, :with_item, move:, box:, confidence_score: 0.3)

        patch move_item_path(move, editing.item),
              params: { item: { name: "Fixed" }, review_suggestion_id: editing.id }

        expect(editing.reload.state).to eq("corrected")
        expect(editing.item.review_state).to eq("confirmed")
        expect(response).to redirect_to(move_box_review_path(move, box, nxt))
      end

      it "returns to the queue when no suggestions remain" do
        editing = create(:recognition_suggestion, :with_item, move:, box:, state: "pending")

        patch move_item_path(move, editing.item),
              params: { item: { name: "Fixed" }, review_suggestion_id: editing.id }

        expect(editing.reload.state).to eq("corrected")
        expect(response).to redirect_to(move_box_review_index_path(move, box))
      end

      it "resolves a conflict on save even though its item points at a different suggestion" do
        confirmed = create(:item, :confirmed, move:, box:, name: "Skillet")
        conflict = create(:recognition_suggestion, :conflict, move:, box:, item: confirmed)

        patch move_item_path(move, confirmed),
              params: { item: { name: "Cast Skillet" }, review_suggestion_id: conflict.id }

        expect(conflict.reload.state).to eq("corrected")
        expect(response).to redirect_to(move_box_review_index_path(move, box))
      end

      it "ignores a carried suggestion that belongs to a different item (stale/crafted form)" do
        edited = create(:item, :manual, move:, box:, name: "Lamp")
        unrelated = create(:recognition_suggestion, :with_item, move:, box:, state: "pending")

        patch move_item_path(move, edited),
              params: { item: { name: "Desk Lamp" }, review_suggestion_id: unrelated.id }

        # The unrelated suggestion (and its linked item) is left untouched…
        expect(unrelated.reload.state).to eq("pending")
        expect(unrelated.item.review_state).not_to eq("confirmed")
        # …and we fall back to a plain item-edit redirect rather than the review flow.
        expect(edited.reload.name).to eq("Desk Lamp")
        expect(response).to redirect_to(move_item_path(move, edited))
      end
    end
  end

  describe "PATCH /moves/:move_id/items/:id/move" do
    it "moves the item to the target box, keeping presence in_box" do
      target = create(:box, move:)
      item = create(:item, :manual, move:, box:)

      patch move_move_item_path(move, item), params: { target_box_id: target.id }

      expect(item.reload.box).to eq(target)
      expect(item.presence_state).to eq("in_box")
    end
  end

  describe "PATCH mark_removed / restore" do
    it "toggles presence without changing review state" do
      item = create(:item, :manual, move:, box:)

      patch mark_removed_move_item_path(move, item)
      expect(item.reload.presence_state).to eq("removed")
      expect(item.review_state).to eq("confirmed")

      patch restore_move_item_path(move, item)
      expect(item.reload.presence_state).to eq("in_box")
    end
  end

  describe "archived Move (viewer cannot mutate)" do
    let(:move) { create(:move, :archived, created_by: user) }

    it "redirects a create attempt away with the archived notice" do
      expect do
        post move_box_items_path(move, box), params: { item: { name: "Nope" } }
      end.not_to change(Item, :count)

      expect(response).to redirect_to(move_boxes_path(move))
      # The full archived alert (not the short moves.read_only status label —
      # the two keys must not collide in YAML).
      expect(flash[:alert]).to eq(I18n.t("moves.archived_alert"))
    end
  end
end
