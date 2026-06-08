# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Scans" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/scan" do
    it "renders the scanner page" do
      get move_scan_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("scans.show.aim"))
    end
  end

  describe "GET /moves/:move_id/scan/:token" do
    it "resolves a known token to the resolved state and never changes status" do
      box = create(:box, :with_room, move:, status: "sealed", qr_token: "tok-live")

      get move_scan_resolve_path(move, "tok-live")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("scans.resolved.success"))
      expect(response.body).to include(I18n.t("scans.resolved.open"))
      expect(box.reload.status).to eq("sealed")
    end

    it "renders the non-disclosing unrecognized state for an unknown token" do
      get move_scan_resolve_path(move, "not-a-real-token")

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include(I18n.t("scans.unrecognized.title"))
      # Must not hint the token might exist elsewhere.
      expect(response.body).not_to include("another")
    end

    it "renders the read-only archived state when the box's Move is archived" do
      archived = create(:move, :archived, created_by: user)
      create(:box, move: archived, qr_token: "tok-arch", status: "sealed")

      get move_scan_resolve_path(archived, "tok-arch")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("scans.archived.eyebrow"))
    end
  end
end
