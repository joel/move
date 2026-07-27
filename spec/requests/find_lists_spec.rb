# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FindLists" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/find_list" do
    it "groups entries by box in numeric order with linked headers and struck found items" do
      room = create(:room, move:, name: "Bedroom")
      late_box = create(:box, move:, number: "11")
      early_box = create(:box, move:, number: "7", room:)
      create(:find_list_entry, move:, user:, item: create(:item, move:, box: late_box, name: "Lamp"))
      create(:find_list_entry, move:, user:,
                               item: create(:item, move:, box: early_box, name: "Charger",
                                                   presence_state: "removed"))

      get move_find_list_path(move)

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("find_lists.show.title"))
        expect(response.body).to include("#{I18n.t("find_lists.show.box_label", number: "7")} · Bedroom")
        expect(response.body).to include(move_box_path(move, early_box)).and include(move_box_path(move, late_box))
        expect(response.body.index("Box 7")).to be < response.body.index("Box 11")
        expect(response.body).to include("line-through").and include(I18n.t("find_lists.show.found"))
        expect(response.body).to include(I18n.t("find_lists.show.found_count", found: 1, total: 2))
        expect(response.body).to include(move_find_list_clear_found_path(move))
      end
    end

    it "omits the clear button when nothing is found and shows the empty state with no entries" do
      box = create(:box, move:)
      create(:find_list_entry, move:, user:, item: create(:item, move:, box:, name: "Lamp"))

      get move_find_list_path(move)
      expect(response.body).not_to include(move_find_list_clear_found_path(move))

      FindListEntry.delete_all
      get move_find_list_path(move)
      expect(response.body).to include(I18n.t("find_lists.show.empty.title"))
        .and include(move_search_path(move))
    end

    # Row-control rendering is asserted here rather than in an isolated
    # component spec — the repo convention for button_to-bearing components.
    it "offers the swipe and inline found controls to an editor" do
      box = create(:box, move:)
      item = create(:item, move:, box:, name: "Lamp")
      create(:find_list_entry, move:, user:, item:)

      get move_find_list_path(move)

      aggregate_failures do
        expect(response.body).to include("swipe-actions")
        expect(response.body).to include(move_find_list_mark_found_path(move, item_id: item.id))
        expect(response.body).to include("find-list-swipe-found-#{item.id}")
          .and include("find-list-row-found-#{item.id}")
        expect(response.body).to include("find-list-swipe-unpin-#{item.id}")
          .and include("find-list-row-unpin-#{item.id}")
      end
    end

    it "flips the found control to restore on a struck row" do
      box = create(:box, move:)
      item = create(:item, move:, box:, name: "Lamp", presence_state: "removed")
      create(:find_list_entry, move:, user:, item:)

      get move_find_list_path(move)

      expect(response.body).to include(move_find_list_restore_path(move, item_id: item.id))
      expect(response.body).not_to include(move_find_list_mark_found_path(move, item_id: item.id))
    end

    it "hides the found controls from a viewer but keeps unpin (personal row)" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)
      box = create(:box, move:)
      item = create(:item, move:, box:, name: "Lamp")
      create(:find_list_entry, move:, user: viewer, item:)

      get move_find_list_path(move)

      aggregate_failures do
        expect(response.body).not_to include(move_find_list_mark_found_path(move, item_id: item.id))
        expect(response.body).to include(move_find_list_unpin_path(move, item_id: item.id))
      end
    end

    it "never shows another user's entries" do
      other = create(:user)
      box = create(:box, move:)
      create(:find_list_entry, move:, user: other, item: create(:item, move:, box:, name: "Secret Lamp"))

      get move_find_list_path(move)

      expect(response.body).not_to include("Secret Lamp")
      expect(response.body).to include(I18n.t("find_lists.show.empty.title"))
    end
  end

  describe "POST/DELETE pin toggles" do
    it "pins over turbo_stream, replacing both toggle variants, the pill and the list, with a toast" do
      box = create(:box, move:)
      item = create(:item, move:, box:, name: "Kettle")

      post move_find_list_pin_path(move, item_id: item.id), as: :turbo_stream

      aggregate_failures do
        expect(FindListEntry.where(move:, user_id: user.id, item:)).to exist
        expect(response.body).to include(%(target="#{Components::FindLists::Toggle.dom_id(item)}"))
        expect(response.body).to include(%(target="#{Components::FindLists::Toggle.dom_id(item, labeled: true)}"))
        expect(response.body).to include(%(target="#{Components::FindLists::SearchLink::ID}"))
        expect(response.body).to include(%(target="#{Components::FindLists::List::ID}"))
        expect(response.body).to include(I18n.t("find_lists.search_link", count: 1))
        # UX rule 1: the pin lands off-screen, so it confirms with a LINKING toast.
        expect(response.body).to include(I18n.t("find_lists.flash.pinned", name: "Kettle"))
        expect(response.body).to include(I18n.t("find_lists.flash.view"))
      end
    end

    it "keeps the pinned toggle state on an item update validation re-render (Codex #733)" do
      box = create(:box, move:)
      item = create(:item, :manual, move:, box:, name: "Kettle")
      create(:find_list_entry, move:, user:, item:)

      patch move_item_path(move, item), params: { item: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("find_lists.toggle.on_list"))
      expect(response.body).not_to include(I18n.t("find_lists.toggle.add_short"))
    end

    it "unpins over turbo_stream and falls back to a list redirect for HTML" do
      box = create(:box, move:)
      item = create(:item, move:, box:, name: "Kettle")
      create(:find_list_entry, move:, user:, item:)

      delete move_find_list_unpin_path(move, item_id: item.id)

      expect(response).to redirect_to(move_find_list_path(move))
      expect(FindListEntry.where(move:, user_id: user.id)).to be_empty
    end

    it "404s pinning a foreign or discarded item" do
      foreign_move = create(:move, created_by: create(:user))
      foreign_item = create(:item, move: foreign_move, box: create(:box, move: foreign_move))

      post move_find_list_pin_path(move, item_id: foreign_item.id)
      expect(response).to have_http_status(:not_found)

      discarded = create(:item, move:, box: create(:box, move:))
      discarded.discard!
      post move_find_list_pin_path(move, item_id: discarded.id)
      expect(response).to have_http_status(:not_found)
    end

    it "keeps the pill count in step with the visible list when a pinned item is soft-deleted" do
      box = create(:box, move:)
      doomed = create(:item, move:, box:, name: "Doomed Lamp")
      create(:find_list_entry, move:, user:, item: doomed)
      doomed.discard!

      get move_search_path(move)

      expect(response.body).not_to include(I18n.t("find_lists.search_link", count: 1))
    end

    it "lets a viewer pin on someone else's move" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)
      box = create(:box, move:)
      item = create(:item, move:, box:, name: "Kettle")

      post move_find_list_pin_path(move, item_id: item.id)

      expect(response).to redirect_to(move_find_list_path(move))
      expect(FindListEntry.where(move:, user_id: viewer.id, item:)).to exist
    end

    it "lets a member pin on an archived move (personal rows only)" do
      archived = create(:move, :archived, created_by: user)
      item = create(:item, move: archived, box: create(:box, move: archived), name: "Kettle")

      post move_find_list_pin_path(archived, item_id: item.id)

      expect(FindListEntry.where(move: archived, user_id: user.id, item:)).to exist
    end
  end

  describe "PATCH mark found / restore" do
    it "marks a pinned item found over turbo_stream even on a sealed box" do
      box = create(:box, move:, status: "sealed")
      item = create(:item, move:, box:, name: "Face Cream")
      create(:find_list_entry, move:, user:, item:)

      patch move_find_list_mark_found_path(move, item_id: item.id), as: :turbo_stream

      aggregate_failures do
        expect(item.reload.presence_state).to eq("removed")
        expect(response.body).to include(%(target="#{Components::FindLists::List::ID}"))
        expect(response.body).to include("line-through").and include(I18n.t("find_lists.show.found"))
        expect(response.body).to include(I18n.t("find_lists.show.found_count", found: 1, total: 1))
      end
    end

    it "restores a found item back into its box" do
      box = create(:box, move:, status: "unpacking")
      item = create(:item, move:, box:, name: "Face Cream", presence_state: "removed")
      create(:find_list_entry, move:, user:, item:)

      patch move_find_list_restore_path(move, item_id: item.id), as: :turbo_stream

      aggregate_failures do
        expect(item.reload.presence_state).to eq("in_box")
        expect(response.body).to include(%(target="#{Components::FindLists::List::ID}"))
        expect(response.body).not_to include("line-through")
      end
    end

    it "falls back to a list redirect for HTML" do
      box = create(:box, move:)
      item = create(:item, move:, box:, name: "Face Cream")
      create(:find_list_entry, move:, user:, item:)

      patch move_find_list_mark_found_path(move, item_id: item.id)

      expect(response).to redirect_to(move_find_list_path(move))
      expect(item.reload.presence_state).to eq("removed")
    end

    it "refuses a viewer (shared-Item mutation, unlike the personal pin)" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)
      box = create(:box, move:)
      item = create(:item, move:, box:, name: "Face Cream")
      create(:find_list_entry, move:, user: viewer, item:)

      patch move_find_list_mark_found_path(move, item_id: item.id)

      expect(response).to have_http_status(:forbidden)
      expect(item.reload.presence_state).to eq("in_box")
    end

    it "redirects with the read-only alert on an archived move" do
      archived = create(:move, :archived, created_by: user)
      item = create(:item, move: archived, box: create(:box, move: archived), name: "Face Cream")
      create(:find_list_entry, move: archived, user:, item:)

      patch move_find_list_mark_found_path(archived, item_id: item.id)

      aggregate_failures do
        expect(response).to redirect_to(move_find_list_path(archived))
        expect(flash[:alert]).to eq(I18n.t("moves.archived_alert"))
        expect(item.reload.presence_state).to eq("in_box")
      end
    end

    it "404s a foreign item" do
      foreign_move = create(:move, created_by: create(:user))
      foreign_item = create(:item, move: foreign_move, box: create(:box, move: foreign_move))

      patch move_find_list_mark_found_path(move, item_id: foreign_item.id)

      expect(response).to have_http_status(:not_found)
    end

    # Codex #736: the phase bypass is justified by "retrieving this pinned
    # item", so an unpinned item (stale form or crafted URL) must not flip —
    # the response just re-renders reality.
    it "never marks an unpinned item, streaming the current list instead" do
      box = create(:box, move:, status: "sealed")
      item = create(:item, move:, box:, name: "Face Cream")

      patch move_find_list_mark_found_path(move, item_id: item.id), as: :turbo_stream

      aggregate_failures do
        expect(item.reload.presence_state).to eq("in_box")
        expect(response.body).to include(%(target="#{Components::FindLists::List::ID}"))
      end

      item.update!(presence_state: "removed")
      patch move_find_list_restore_path(move, item_id: item.id), as: :turbo_stream

      expect(item.reload.presence_state).to eq("removed")
    end
  end

  describe "DELETE /moves/:move_id/find_list/found" do
    it "clears struck entries with a toast and leaves live ones" do
      box = create(:box, move:)
      live = create(:find_list_entry, move:, user:, item: create(:item, move:, box:, name: "Live"))
      create(:find_list_entry, move:, user:,
                               item: create(:item, move:, box:, name: "Found", presence_state: "removed"))

      delete move_find_list_clear_found_path(move), as: :turbo_stream

      aggregate_failures do
        expect(response.body).to include(%(target="#{Components::FindLists::List::ID}"))
        expect(response.body).to include(I18n.t("find_lists.flash.cleared", count: 1))
        expect(FindListEntry.where(move:, user_id: user.id)).to contain_exactly(live)
      end
    end
  end
end
