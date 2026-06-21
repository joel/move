# frozen_string_literal: true

require "rails_helper"

# The async bulk label-print flow (#303). The test queue adapter is :inline, so a
# POST to create runs GenerateJob synchronously — by the time we follow the redirect
# the run is completed and downloadable.
RSpec.describe "Label Print Runs" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) } # creator → member

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
    # NB: do NOT stub Apartment::Tenant.current — the inline GenerateJob switches to
    # it, and a fake "acme" schema doesn't exist in the test DB (it would raise
    # TenantNotFound). Leaving it real means the job runs in the test schema where
    # these boxes live (mirrors spec/requests/captures_spec.rb's inline-job setup).
    [1, 2, 3, 5].each { |n| create(:box, :with_room, move:, number: n.to_s) } # gap at 4
  end

  describe "POST /moves/:move_id/label_print/runs" do
    it "starts a run and redirects to its progress page" do
      expect do
        post move_label_print_runs_path(move), params: { from: 2, to: 5 }
      end.to change(LabelPrintRun, :count).by(1)

      run = LabelPrintRun.last
      expect(run.total_count).to eq(3) # boxes 2,3,5
      expect(response).to redirect_to(move_label_print_run_path(move, run))
    end

    it "generates a downloadable PDF (job runs inline)" do
      post move_label_print_runs_path(move), params: { from: 2, to: 5 }
      run = LabelPrintRun.last

      expect(run.reload).to be_ready
      get download_move_label_print_run_path(move, run)

      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("attachment").and include("boxes-002-005")
      expect(response.body[0, 4]).to eq("%PDF")
      expect(response.body).to include("/Count 6") # 3 boxes × 2 pages
    end

    it "re-renders the form with an error (and no run) for from > to" do
      expect do
        post move_label_print_runs_path(move), params: { from: 5, to: 2 }
      end.not_to change(LabelPrintRun, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("label_print.errors.invalid_range"))
    end

    it "rejects a non-numeric / over-bigint bound without 500ing" do
      post move_label_print_runs_path(move), params: { from: 1, to: "#{Box::MAX_NUMBER}0" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("label_print.errors.invalid_range"))
    end

    it "shows the empty-range error when no boxes match" do
      post move_label_print_runs_path(move), params: { from: 90, to: 99 }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("label_print.errors.empty"))
    end

    it "rejects a range over the safety cap" do
      stub_const("LabelPrintRun::MAX_LABELS", 2)
      post move_label_print_runs_path(move), params: { from: 1, to: 5 } # 4 boxes > 2
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("label_print.errors.too_many", max: 2))
    end

    it "404s a non-member" do
      stub_current_user(create(:user))
      post move_label_print_runs_path(move), params: { from: 1, to: 2 }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /moves/:move_id/label_print/runs/:id" do
    it "renders the live progress page subscribed to the run stream" do
      run = create(:label_print_run, :processing, move:)
      get move_label_print_run_path(move, run)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("label_print.status.progress_label"))
    end

    it "shows the Download link when the run is ready" do
      run = create(:label_print_run, :completed, move:)
      get move_label_print_run_path(move, run)
      expect(response.body).to include(I18n.t("label_print.status.download"))
      expect(response.body).to include(download_move_label_print_run_path(move, run))
    end

    it "shows a Try again link when the run failed" do
      run = create(:label_print_run, :failed, move:)
      get move_label_print_run_path(move, run)
      expect(response.body).to include(I18n.t("label_print.status.retry"))
    end
  end

  describe "GET download before ready" do
    it "redirects back to the progress page while still generating" do
      run = create(:label_print_run, :processing, move:)
      get download_move_label_print_run_path(move, run)
      expect(response).to redirect_to(move_label_print_run_path(move, run))
    end
  end
end
