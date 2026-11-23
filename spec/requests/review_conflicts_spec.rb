# frozen_string_literal: true

require "rails_helper"

# #881 — settling a conflict (a detection that matched an item already confirmed
# in the box) from the per-photo review: "Same item" or "Keep both".
RSpec.describe "Review conflict resolution" do
  let(:user) { create(:user) }
  let(:lamp) { create(:item, move: create(:move, created_by: user), name: "Lamp", review_state: "confirmed") }
  let!(:suggestion) do
    create(:recognition_suggestion, :conflict, move: lamp.move, box: lamp.box, item: lamp,
                                               proposed_name: "Lamp")
  end

  # Derived from the suggestion (plain methods keep the memoized-helper count down).
  delegate :move, :box, :media, to: :suggestion

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  def item_list
    response.parsed_body.at_css("##{Components::Reviews::ItemList::ID}")
  end

  def dismiss_path = move_box_review_dismiss_conflict_path(move, box, media, suggestion)
  def keep_both_path = move_box_review_keep_both_conflict_path(move, box, media, suggestion)

  describe "the review page" do
    it "offers Same item and Keep both on each match for an editor" do
      get move_box_review_photo_path(move, box, media)

      expect(item_list.at_css(%(form[action="#{dismiss_path}"]))).to be_present
      expect(item_list.at_css(%(form[action="#{keep_both_path}"]))).to be_present
      expect(item_list.at_css(%(a[href="#{move_item_path(move, lamp)}"]))).to be_present
    end

    it "shows the matches without controls to a viewer" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      get move_box_review_photo_path(move, box, media)

      expect(item_list.at_css(%(a[href="#{move_item_path(move, lamp)}"]))).to be_present
      expect(item_list.at_css(%(form[action="#{dismiss_path}"]))).to be_nil
      expect(item_list.at_css(%(form[action="#{keep_both_path}"]))).to be_nil
    end

    it "shows no controls on an archived Move" do
      move.update!(status: "archived")

      get move_box_review_photo_path(move, box, media)

      expect(item_list.at_css(%(a[href="#{move_item_path(move, lamp)}"]))).to be_present
      expect(item_list.at_css("form")).to be_nil
    end

    it "lists the matches after the photo's own items" do
      create(:item, move:, box:, source_media: media, name: "Kettle", review_state: "pending_review")

      get move_box_review_photo_path(move, box, media)

      expect(item_list.text).to include("Kettle").and include(I18n.t("reviews.photo.conflict_title"))
      expect(item_list.at_css(%(form[action="#{keep_both_path}"]))).to be_present
    end

    it "drops the match once it is settled" do
      suggestion.update!(state: "accepted")

      get move_box_review_photo_path(move, box, media)

      expect(item_list.text).to include(I18n.t("reviews.photo.empty_title"))
      expect(item_list.at_css("form")).to be_nil
    end
  end

  describe "POST .../dismiss" do
    it "accepts the match, re-renders the list in place and links the matched item" do
      expect { post dismiss_path, as: :turbo_stream }.not_to change(Item, :count)

      expect(response).to have_http_status(:ok)
      expect(suggestion.reload.state).to eq("accepted")
      expect(response.body).to include(%(target="#{Components::Reviews::ItemList::ID}"))
      expect(response.body).to include(I18n.t("reviews.photo.empty_title"))
      expect(response.body).to include(move_item_path(move, lamp))
    end

    it "redirects an HTML client back to the photo with a linking notice" do
      post dismiss_path

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media))
      expect(flash[:notice]).to eq(I18n.t("reviews.flash.conflict_dismissed", name: "Lamp"))
      expect(flash[:action_href]).to eq(move_item_path(move, lamp))
    end
  end

  describe "POST .../keep_both" do
    it "adds a second item, highlights it in the list and links it" do
      expect { post keep_both_path, as: :turbo_stream }.to change(Item, :count).by(1)

      second = Item.order(:created_at).last
      expect(second).to have_attributes(name: "Lamp", source_media_id: media.id, review_state: "confirmed")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(Components::Reviews::ItemRow.dom_id(second))
      expect(response.body).to include(move_item_path(move, second))
    end

    it "keeps the queue walk param on the HTML redirect" do
      post move_box_review_keep_both_conflict_path(move, box, media, suggestion, queue: "move")

      expect(response).to redirect_to(move_box_review_photo_path(move, box, media, queue: "move"))
    end

    it "is a no-op with a notice when the match was already settled" do
      post keep_both_path, as: :turbo_stream

      expect { post keep_both_path, as: :turbo_stream }.not_to change(Item, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("reviews.flash.conflict_stale"))
    end

    it "is a no-op with the stale notice when the matched item was deleted meanwhile (#909)" do
      Items::Remove.new.call(item: lamp, actor: user)

      expect { post keep_both_path, as: :turbo_stream }.not_to change(Item, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("reviews.flash.conflict_stale"))
      expect(suggestion.reload.state).to eq("conflict")
    end
  end

  describe "guards" do
    it "refuses a viewer" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      expect { post keep_both_path }.not_to change(Item, :count)
      expect(response).to have_http_status(:forbidden)
      expect(suggestion.reload.state).to eq("conflict")
    end

    it "redirects with the read-only alert on an archived Move" do
      move.update!(status: "archived")

      expect { post keep_both_path }.not_to change(Item, :count)
      # ReviewsController#read_only_redirect_path — the box, as for every review mutation.
      expect(response).to redirect_to(move_box_path(move, box))
      expect(flash[:alert]).to eq(I18n.t("moves.archived_alert"))
    end

    it "404s a suggestion from another photo" do
      other = create(:media, move:, box:)

      post move_box_review_dismiss_conflict_path(move, box, other, suggestion)

      expect(response).to have_http_status(:not_found)
      expect(suggestion.reload.state).to eq("conflict")
    end
  end
end
