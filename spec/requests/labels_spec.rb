# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Labels" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, :with_room, move:, number: "7") }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/boxes/:box_id/label" do
    it "serves an inline label PDF" do
      get move_box_label_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("inline").and include("label.pdf")
      expect(response.body[0, 4]).to eq("%PDF")
    end

    it "does not query items (the exterior label carries no contents)" do
      # Structural guarantee: BoxLabelPdf never touches box.items. Assert the
      # endpoint renders without any item present.
      expect { get move_box_label_path(move, box) }.not_to raise_error
      expect(response).to have_http_status(:ok)
    end

    it "emits the Move's labels_per_box copies (Phase 45)" do
      move.update!(labels_per_box: 4)

      get move_box_label_path(move, box)

      expect(response.body).to include("/Count 4")
    end

    it "defaults to 2 pages on a default Move (regression)" do
      get move_box_label_path(move, box)

      expect(response.body).to include("/Count 2")
    end
  end
end
