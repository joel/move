require "rails_helper"

RSpec.describe "Vocabularies" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  # Admin membership — vocabulary management is admin-only.
  before do
    create(:move_membership, :admin, move:, user:)
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/vocabularies/:kind" do
    it "renders the categories surface with its values" do
      create(:category, move:, name: "Kitchenware")

      get move_vocabularies_path(move, "categories")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Manage Categories").and include("Kitchenware")
    end

    it "shows a tag's applies-to facet" do
      create(:tag, :box, move:, name: "Heavy")

      get move_vocabularies_path(move, "tags")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Manage Tags").and include("Heavy")
      expect(response.body).to include(I18n.t("vocabularies.applies_to.box"))
    end

    it "renders the rooms surface and the empty state when there are none" do
      get move_vocabularies_path(move, "rooms")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("vocabularies.rooms.empty_title"))
    end

    it "404s for an unknown kind" do
      get "/moves/#{move.id}/vocabularies/widgets"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /moves/:move_id/vocabularies/:kind" do
    it "adds a category and redirects" do
      expect do
        post move_vocabularies_path(move, "categories"), params: { vocabulary: { name: "Books" } }
      end.to change(move.categories, :count).by(1)

      expect(response).to redirect_to(move_vocabularies_path(move, "categories"))
    end

    it "adds a tag with applies_to" do
      post move_vocabularies_path(move, "tags"), params: { vocabulary: { name: "Fragile", applies_to: "both" } }

      expect(move.tags.find_by(name: "Fragile").applies_to).to eq("both")
    end

    it "re-renders with an error for a blank name" do
      post move_vocabularies_path(move, "categories"), params: { vocabulary: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /moves/:move_id/vocabularies/:kind/:id" do
    it "renames a value" do
      category = create(:category, move:, name: "Bookz")

      patch move_vocabulary_path(move, "categories", category), params: { vocabulary: { name: "Books" } }

      expect(category.reload.name).to eq("Books")
      expect(response).to redirect_to(move_vocabularies_path(move, "categories"))
    end

    it "re-opens the inline edit form with the error on a failed rename" do
      category = create(:category, move:, name: "Books")

      patch move_vocabulary_path(move, "categories", category), params: { vocabulary: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      # The edited row reopens its form showing why the save failed.
      expect(response.body).to include("can&#39;t be blank").or include("can't be blank")
      expect(category.reload.name).to eq("Books")
    end
  end

  describe "DELETE /moves/:move_id/vocabularies/:kind/:id" do
    it "removes a value and detaches it" do
      room = create(:room, move:)
      box = create(:box, move:, room:)

      expect do
        delete move_vocabulary_path(move, "rooms", room)
      end.to change(move.rooms, :count).by(-1)

      expect(box.reload.room_id).to be_nil
    end
  end

  describe "admin enforcement" do
    let(:plain_member) { create(:user) }

    before do
      create(:move_membership, move:, user: plain_member, role: "member")
      stub_current_user(plain_member)
    end

    it "lets a non-admin member view but hides edit affordances" do
      create(:category, move:, name: "Kitchenware")

      get move_vocabularies_path(move, "categories")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Kitchenware")
      expect(response.body).not_to include(I18n.t("vocabularies.categories.add"))
    end

    it "rejects a non-admin member's create" do
      post move_vocabularies_path(move, "categories"), params: { vocabulary: { name: "Books" } }

      expect(response).to have_http_status(:forbidden)
      expect(move.categories.count).to eq(0)
    end

    it "rejects a non-admin member's destroy" do
      category = create(:category, move:, name: "Books")

      delete move_vocabulary_path(move, "categories", category)

      expect(response).to have_http_status(:forbidden)
      expect(Category.exists?(category.id)).to be(true)
    end
  end
end
