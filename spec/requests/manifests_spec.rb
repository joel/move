# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Manifests" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, :with_room, move:, number: "7") }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/boxes/:box_id/manifest" do
    it "serves an inline A4 manifest PDF" do
      create(:item, :manual, move:, box:, name: "Reading Lamp")

      get move_box_manifest_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("inline").and include("manifest.pdf")
      expect(response.body[0, 4]).to eq("%PDF")
    end

    it "records the sensitive read as a manifest.viewed audit event" do
      allow(Rails.event).to receive(:notify)

      get move_box_manifest_path(move, box)

      expect(Rails.event).to have_received(:notify).with(
        "manifest.viewed", hash_including(box_id: box.id, move_id: move.id, actor_id: user.id)
      )
    end
  end
end
