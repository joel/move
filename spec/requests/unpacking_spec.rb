require "rails_helper"

RSpec.describe "Unpacking" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/boxes/:box_id/unpacking" do
    it "renders the checklist for a box being unpacked" do
      box = create(:box, :with_room, move:, number: "7", status: "unpacking")
      create(:item, move:, box:, name: "Ceramic Plates", presence_state: "in_box")
      create(:item, move:, box:, name: "Coffee Maker", presence_state: "removed")

      get move_box_unpacking_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("unpacking.remaining_title"))
        .and include("Ceramic Plates").and include("Coffee Maker")
        .and include(I18n.t("unpacking.remaining_count", count: 1, total: 2))
    end

    it "renders the celebration for an unpacked box" do
      box = create(:box, :with_room, move:, number: "8", status: "unpacked")

      get move_box_unpacking_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("unpacking.done_title"))
        .and include(I18n.t("unpacking.back_to_boxes"))
    end

    it "redirects to the box when it isn't being unpacked yet" do
      box = create(:box, :with_room, move:, status: "sealed")

      get move_box_unpacking_path(move, box)

      expect(response).to redirect_to(move_box_path(move, box))
    end
  end

  describe "PATCH .../unpacking/items/:item_id/remove" do
    it "marks the item removed and returns to the checklist" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(item.reload.presence_state).to eq("removed")
    end
  end

  describe "PATCH .../unpacking/items/:item_id/restore" do
    it "restores a removed item to the box" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "removed")

      patch move_box_unpacking_restore_path(move, box, item)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(item.reload.presence_state).to eq("in_box")
    end

    it "refuses to restore on an already-unpacked box (no active checklist)" do
      box = create(:box, :with_room, move:, status: "unpacked")
      item = create(:item, move:, box:, presence_state: "removed")

      patch move_box_unpacking_restore_path(move, box, item)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(item.reload.presence_state).to eq("removed")
    end
  end

  describe "PATCH .../unpacking/items/:item_id/remove on a non-unpacking box" do
    it "refuses to remove when the checklist isn't active" do
      box = create(:box, :with_room, move:, status: "in_transit")
      item = create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(item.reload.presence_state).to eq("in_box")
    end
  end

  describe "PATCH .../remove as Turbo Stream (no reload)" do
    it "streams the row out, refreshes progress, and re-renders the unpacked section" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")
      create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body)
        .to include(%(action="remove" target="#{Components::Unpacking::ItemRow.dom_id(item, :remaining)}"))
        .and include(Components::Unpacking::ProgressCard::ID)
        .and include(Components::Unpacking::UnpackedSection::ID)
      expect(item.reload.presence_state).to eq("removed")
    end

    it "does not re-render the remaining section while items still remain" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")
      create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response.body)
        .not_to include(%(action="replace" target="#{Components::Unpacking::RemainingSection::ID}"))
      expect(response.body).not_to include(I18n.t("unpacking.all_clear_title"))
    end

    it "flips the remaining section to the all-clear empty state when the last item is removed" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_remove_path(move, box, item), as: :turbo_stream

      expect(response.body)
        .to include(%(action="replace" target="#{Components::Unpacking::RemainingSection::ID}"))
        .and include(I18n.t("unpacking.all_clear_title"))
    end
  end

  describe "PATCH .../restore as Turbo Stream (no reload)" do
    it "streams the row out and re-renders the remaining section at sorted position" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, name: "Lamp", presence_state: "removed")
      create(:item, move:, box:, presence_state: "removed")

      patch move_box_unpacking_restore_path(move, box, item), as: :turbo_stream

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body)
        .to include(%(action="remove" target="#{Components::Unpacking::ItemRow.dom_id(item, :unpacked)}"))
        .and include(%(action="replace" target="#{Components::Unpacking::RemainingSection::ID}"))
        .and include("Lamp")
      expect(item.reload.presence_state).to eq("in_box")
    end

    it "hides the unpacked section when the last unpacked item is restored" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "removed")

      patch move_box_unpacking_restore_path(move, box, item), as: :turbo_stream

      expect(response.body)
        .to include(%(action="replace" target="#{Components::Unpacking::UnpackedSection::ID}"))
      # The re-rendered, now-empty unpacked section is hidden.
      expect(response.body).to match(/id="#{Components::Unpacking::UnpackedSection::ID}"[^>]*\bhidden\b/o)
    end
  end

  describe "PATCH .../unpacking/complete" do
    it "marks the box unpacked and cascades remaining items to removed" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_complete_path(move, box)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(box.reload.status).to eq("unpacked")
      expect(item.reload.presence_state).to eq("removed")
    end
  end

  describe "PATCH .../unpacking/reopen" do
    it "reopens an unpacked box without restoring its items" do
      box = create(:box, :with_room, move:, status: "unpacked")
      item = create(:item, move:, box:, presence_state: "removed")

      patch move_box_unpacking_reopen_path(move, box)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(box.reload.status).to eq("unpacking")
      expect(item.reload.presence_state).to eq("removed")
    end
  end

  describe "archived move (read-only)" do
    let(:move) { create(:move, created_by: user, status: "archived") }

    it "renders the checklist without remove forms" do
      box = create(:box, :with_room, move:, status: "unpacking")
      create(:item, move:, box:, presence_state: "in_box")

      get move_box_unpacking_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("unpacking.read_only"))
      expect(response.body).not_to include(move_box_unpacking_complete_path(move, box))
    end

    it "blocks marking the box unpacked" do
      box = create(:box, :with_room, move:, status: "unpacking")
      item = create(:item, move:, box:, presence_state: "in_box")

      patch move_box_unpacking_complete_path(move, box)

      expect(response).to redirect_to(move_box_unpacking_path(move, box))
      expect(box.reload.status).to eq("unpacking")
      expect(item.reload.presence_state).to eq("in_box")
    end
  end
end
