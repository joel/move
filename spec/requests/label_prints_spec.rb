# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Label Prints" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) } # creator → member

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
    allow(Apartment::Tenant).to receive(:current).and_return("acme")
    # Boxes 1, 2, 3, 5 — a gap at 4 (e.g. a discarded box) so the range is sparse.
    [1, 2, 3, 5].each { |n| create(:box, :with_room, move:, number: n.to_s) }
  end

  describe "GET /moves/:move_id/label_print" do
    it "renders the range form" do
      get move_label_print_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("label_print.submit"))
    end

    it "404s a non-member non-disclosingly" do
      stub_current_user(create(:user))

      get move_label_print_path(move)

      expect(response).to have_http_status(:not_found)
    end

    it "hints the numeric max (box 10 is not dropped by a lexical compare)" do
      create(:box, :with_room, move:, number: "10") # alongside 1,2,3,5

      get move_label_print_path(move)

      # Numeric max is 10 — a string compare would pick "9"/"5" and drop box 10.
      expect(response.body).to include(I18n.t("label_print.range_hint", min: 1, max: 10, count: 5))
    end
  end

  describe "GET /moves/:move_id/label_print/labels" do
    it "serves an inline PDF with 2 pages per box in the range" do
      # 2..5 spans boxes 2, 3, 5 (4 is absent) → 3 boxes × 2 pages.
      get move_label_print_labels_path(move, from: 2, to: 5)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"])
        .to include("inline").and include("boxes-002-005-labels.pdf")
      expect(response.body[0, 4]).to eq("%PDF")
      expect(response.body).to include("/Count 6")
    end

    it "rejects from > to with a validation message" do
      get move_label_print_labels_path(move, from: 5, to: 2)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("label_print.errors.invalid_range"))
    end

    it "rejects a non-numeric bound" do
      get move_label_print_labels_path(move, from: "abc", to: 5)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("label_print.errors.invalid_range"))
    end

    it "shows an empty-range message when no boxes match" do
      get move_label_print_labels_path(move, from: 90, to: 99)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("label_print.errors.empty"))
    end

    it "rejects a range over the safety cap" do
      stub_const("LabelPrintsController::MAX_LABELS", 2)

      get move_label_print_labels_path(move, from: 1, to: 5) # 4 boxes > cap 2

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("label_print.errors.too_many", max: 2))
    end
  end
end
