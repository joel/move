require "rails_helper"

RSpec.describe "Vocabularies" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  # The Move creator is its admin (the :move factory wires this), and vocabulary
  # management is admin-only.
  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/vocabularies/:kind" do
    it "renders the rooms surface with its values" do
      create(:room, move:, name: "Kitchen")

      get move_vocabularies_path(move, "rooms")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Manage Rooms").and include("Kitchen")
    end

    it "renders the rooms empty state when there are none" do
      get move_vocabularies_path(move, "rooms")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("vocabularies.rooms.empty_title"))
    end

    it "404s for a removed kind (categories / tags) or an unknown one" do
      %w[categories tags widgets].each do |kind|
        get "/moves/#{move.id}/vocabularies/#{kind}"
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /moves/:move_id/vocabularies/:kind" do
    it "adds a room and redirects" do
      expect do
        post move_vocabularies_path(move, "rooms"), params: { vocabulary: { name: "Attic" } }
      end.to change(move.rooms, :count).by(1)

      expect(response).to redirect_to(move_vocabularies_path(move, "rooms"))
    end

    it "re-streams the add form with an error for a blank name" do
      post move_vocabularies_path(move, "rooms"),
           params: { vocabulary: { name: "" } }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body)
        .to include(%(target="#{Components::Vocabularies::AddForm::ID}"))
        .and include("can&#39;t be blank").or include("can't be blank")
    end

    it "streams the new value into the highlighted list with a toast" do
      post move_vocabularies_path(move, "rooms"),
           params: { vocabulary: { name: "Attic" } }, as: :turbo_stream

      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      room = move.rooms.find_by(name: "Attic")
      expect(response.body)
        .to include(%(action="replace" target="#{Components::Vocabularies::List::ID}"))
        .and include(Components::Vocabularies::Row.dom_id(room))
        .and include("highlight")
        .and include(I18n.t("vocabularies.create.created", name: "Attic"))
    end
  end

  describe "PATCH /moves/:move_id/vocabularies/:kind/:id" do
    it "renames a value" do
      room = create(:room, move:, name: "Kitchn")

      patch move_vocabulary_path(move, "rooms", room), params: { vocabulary: { name: "Kitchen" } }

      expect(room.reload.name).to eq("Kitchen")
      expect(response).to redirect_to(move_vocabularies_path(move, "rooms"))
    end

    it "streams the renamed value back into the highlighted list with a toast" do
      room = create(:room, move:, name: "Kitchn")

      patch move_vocabulary_path(move, "rooms", room),
            params: { vocabulary: { name: "Kitchen" } }, as: :turbo_stream

      expect(response.body)
        .to include(%(action="replace" target="#{Components::Vocabularies::List::ID}"))
        .and include(I18n.t("vocabularies.update.updated", name: "Kitchen"))
      expect(room.reload.name).to eq("Kitchen")
    end

    it "re-streams just the edited row with its form re-opened on a failed rename" do
      room = create(:room, move:, name: "Kitchen")

      patch move_vocabulary_path(move, "rooms", room),
            params: { vocabulary: { name: "" } }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body)
        .to include(%(action="replace" target="#{Components::Vocabularies::Row.dom_id(room)}"))
        .and include(%(data-inline-edit-open-value="true"))
        # The display keeps the persisted name, so canceling reverts to it.
        .and include("Kitchen")
        .and include("can&#39;t be blank").or include("can't be blank")
      expect(room.reload.name).to eq("Kitchen")
    end
  end

  describe "DELETE /moves/:move_id/vocabularies/:kind/:id" do
    it "removes a value and detaches it from its boxes" do
      room = create(:room, move:)
      box = create(:box, move:, room:)

      expect do
        delete move_vocabulary_path(move, "rooms", room)
      end.to change(move.rooms, :count).by(-1)

      expect(box.reload.room_id).to be_nil
    end

    it "streams the row out, and flips to the empty state on the last value" do
      only = create(:room, move:, name: "Sole")

      delete move_vocabulary_path(move, "rooms", only), as: :turbo_stream

      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body)
        .to include(%(action="remove" target="#{Components::Vocabularies::Row.dom_id(only)}"))
        .and include(%(action="replace" target="#{Components::Vocabularies::List::ID}"))
        .and include(I18n.t("vocabularies.rooms.empty_title"))
    end

    it "streams only the row out while other values remain" do
      kept = create(:room, move:, name: "Keep")
      gone = create(:room, move:, name: "Drop")

      delete move_vocabulary_path(move, "rooms", gone), as: :turbo_stream

      expect(response.body).to include(%(action="remove" target="#{Components::Vocabularies::Row.dom_id(gone)}"))
      expect(response.body).not_to include(%(action="replace" target="#{Components::Vocabularies::List::ID}"))
      expect(move.rooms).to include(kept)
    end
  end

  describe "admin enforcement" do
    let(:plain_member) { create(:user) }

    before do
      create(:move_membership, move:, user: plain_member, role: "contributor")
      stub_current_user(plain_member)
    end

    it "lets a non-admin member view but hides edit affordances" do
      create(:room, move:, name: "Kitchen")

      get move_vocabularies_path(move, "rooms")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Kitchen")
      expect(response.body).not_to include(I18n.t("vocabularies.rooms.add"))
    end

    it "rejects a non-admin member's create" do
      post move_vocabularies_path(move, "rooms"), params: { vocabulary: { name: "Attic" } }

      expect(response).to have_http_status(:forbidden)
      expect(move.rooms.count).to eq(0)
    end

    it "rejects a non-admin member's destroy" do
      room = create(:room, move:, name: "Kitchen")

      delete move_vocabulary_path(move, "rooms", room)

      expect(response).to have_http_status(:forbidden)
      expect(Room.exists?(room.id)).to be(true)
    end
  end

  describe "in-use remove confirmation" do
    it "gates the remove form with a Turbo confirm only when the value is in use" do
      in_use = create(:room, move:, name: "Kitchen")
      create(:box, move:, room: in_use)

      get move_vocabularies_path(move, "rooms")

      expect(response.body).to include("data-turbo-confirm")
      expect(response.body).to include("lose its room") # the in-use confirm copy
    end

    it "omits the Turbo confirm when nothing is in use" do
      create(:room, move:, name: "Attic") # no boxes

      get move_vocabularies_path(move, "rooms")

      expect(response.body).not_to include("data-turbo-confirm")
    end
  end

  describe "membership enforcement on view" do
    it "404s a signed-in non-member non-disclosingly (move is out of their scope)" do
      stranger = create(:user) # no move_membership for this Move
      stub_current_user(stranger)
      create(:room, move:, name: "Kitchen")

      get move_vocabularies_path(move, "rooms")

      expect(response).to have_http_status(:not_found)
    end
  end
end
