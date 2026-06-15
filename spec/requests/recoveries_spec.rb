# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Photo recovery" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:) }
  let(:media) { create(:media, move:, box:) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET .../recovery/photo/:media_id" do
    it "shows the reason, retry, and manual-add for a failed photo" do
      create(:recognition_run, :failed, move:, box:, media:,
                                        error_message: "RecognitionProviders::Openai request failed (429): " \
                                                       "You exceeded your current quota, please check your plan and billing details.")

      get move_box_recovery_photo_path(move, box, media)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("ui.recognition_errors.quota"))
      expect(response.body).to include(I18n.t("recoveries.actions.retry"))
      expect(response.body).to include(new_move_box_item_path(move, box, source_media_id: media.id))
      expect(response.body).not_to include("RecognitionProviders::Openai")
    end

    it "offers manual-add but no retry for a zero-detection photo" do
      create(:recognition_run, :succeeded, move:, box:, media:)

      get move_box_recovery_photo_path(move, box, media)

      expect(response.body).to include(I18n.t("recoveries.actions.add_item"))
      expect(response.body).not_to include(I18n.t("recoveries.actions.retry"))
    end

    it "redirects a resolved photo (now has an item) to that item" do
      create(:recognition_run, :failed, move:, box:, media:)
      item = create(:item, move:, box:, source_media: media, name: "Lamp")

      get move_box_recovery_photo_path(move, box, media)

      expect(response).to redirect_to(move_item_path(move, item))
    end

    it "redirects a moved-item photo to the item, not the original box's empty walk" do
      other_box = create(:box, move:, number: "9")
      create(:recognition_run, :failed, move:, box:, media:)
      item = create(:item, move:, box: other_box, source_media: media, name: "Lamp")

      get move_box_recovery_photo_path(move, box, media)

      expect(response).to redirect_to(move_item_path(move, item))
    end

    it "redirects a conflict-only photo (suggestions but no item) — not orphaned" do
      run = create(:recognition_run, :succeeded, move:, box:, media:)
      create(:recognition_suggestion, :conflict, move:, box:, media:, recognition_run: run)

      get move_box_recovery_photo_path(move, box, media)

      expect(response).to redirect_to(move_box_path(move, box))
    end
  end

  describe "GET .../recovery/photo/:media_id/state (poll fragment)" do
    it "renders only the status fragment, not the full app shell" do
      create(:recognition_run, :failed, move:, box:, media:)

      get move_box_recovery_photo_state_path(move, box, media)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-pending")
      # The recognition poller injects this into a small frame — it must not carry
      # the AppShell layout (brand tagline lives only in the chrome).
      expect(response.body).not_to include(I18n.t("ui.nav.brand_tagline"))
    end

    it "shows a resolved state (no manual add) when a retry result is conflict-only" do
      run = create(:recognition_run, :succeeded, move:, box:, media:)
      create(:recognition_suggestion, :conflict, move:, box:, media:, recognition_run: run)

      get move_box_recovery_photo_state_path(move, box, media)

      expect(response.body).to include(I18n.t("recoveries.conflict.title"))
      expect(response.body).not_to include(I18n.t("recoveries.actions.add_item"))
    end
  end

  describe "POST .../recovery/photo/:media_id/retry" do
    it "enqueues a fresh run for a failed photo and redirects back" do
      create(:recognition_run, :failed, move:, box:, media:)

      expect do
        post move_box_recovery_photo_retry_path(move, box, media)
      end.to change(media.recognition_runs, :count).by(1)

      expect(response).to redirect_to(move_box_recovery_photo_path(move, box, media))
    end

    it "is a no-op for a non-failed run (not retryable)" do
      create(:recognition_run, :succeeded, move:, box:, media:)

      expect do
        post move_box_recovery_photo_retry_path(move, box, media)
      end.not_to change(media.recognition_runs, :count)
    end

    it "does not re-run a photo resolved since the page loaded (stale retry)" do
      create(:recognition_run, :failed, move:, box:, media:)
      create(:item, move:, box:, source_media: media, name: "Lamp") # resolved meanwhile

      expect do
        post move_box_recovery_photo_retry_path(move, box, media)
      end.not_to change(media.recognition_runs, :count)

      expect(response).to redirect_to(move_box_recovery_photo_path(move, box, media))
    end
  end

  describe "manual add bound to the photo" do
    it "attaches the new item to the photo so it leaves the orphaned set" do
      create(:recognition_run, :failed, move:, box:, media:)

      post move_box_items_path(move, box),
           params: { item: { name: "Desk lamp", quantity: "1", source_media_id: media.id } }

      item = box.items.find_by(name: "Desk lamp")
      expect(item.source_media_id).to eq(media.id)
    end

    it "drops the binding (still creates the item) when the photo is no longer orphaned" do
      run = create(:recognition_run, :succeeded, move:, box:, media:)
      create(:recognition_suggestion, :conflict, move:, box:, media:, recognition_run: run)

      post move_box_items_path(move, box),
           params: { item: { name: "Desk lamp", quantity: "1", source_media_id: media.id } }

      item = box.items.find_by(name: "Desk lamp")
      expect(item).to be_present
      expect(item.source_media_id).to be_nil
    end

    it "does not bind to a photo whose recognition is still in flight" do
      create(:recognition_run, :processing, move:, box:, media:)

      post move_box_items_path(move, box),
           params: { item: { name: "Desk lamp", quantity: "1", source_media_id: media.id } }

      item = box.items.find_by(name: "Desk lamp")
      expect(item).to be_present
      expect(item.source_media_id).to be_nil
    end
  end
end
