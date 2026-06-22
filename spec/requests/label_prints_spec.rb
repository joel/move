# frozen_string_literal: true

require "rails_helper"

# The range-picker form. Submitting it POSTs a run — that async flow (create / show /
# download / validation) lives in spec/requests/label_print_runs_spec.rb.
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
    it "renders the range form posting to the runs endpoint" do
      get move_label_print_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("label_print.submit"))
      expect(response.body).to include(move_label_print_runs_path(move))
    end

    it "reflects the Move's labels_per_box in the subtitle (#310)" do
      move.update!(labels_per_box: 5)

      get move_label_print_path(move)

      expect(response.body).to include(I18n.t("label_print.subtitle", copies: 5))
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
end
