# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Insurance dossier runs" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  def seed_item
    box = create(:box, move:, number: "1")
    create(:item, :manual, move:, box:, name: "Mug")
  end

  describe "POST /moves/:move_id/insurance/dossier/runs" do
    it "starts a run and redirects to its progress page" do
      seed_item
      allow(InsuranceDossierRuns::GenerateJob).to receive(:perform_later)

      post move_insurance_dossier_runs_path(move)

      run = move.insurance_dossier_runs.last
      expect(response).to redirect_to(move_insurance_dossier_run_path(move, run))
    end

    it "redirects to the hub with an alert when there is nothing to export" do
      post move_insurance_dossier_runs_path(move)

      expect(response).to redirect_to(move_insurance_path(move))
      expect(flash[:alert]).to eq(I18n.t("insurance.errors.empty"))
    end

    it "403s a contributor (the dossier is admin-only)" do
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)
      seed_item

      post move_insurance_dossier_runs_path(move)

      expect(response).not_to have_http_status(:redirect)
      expect(move.insurance_dossier_runs.count).to eq(0)
    end
  end

  describe "GET .../runs/:id" do
    it "renders the live progress page" do
      run = create(:insurance_dossier_run, :processing, move:)

      get move_insurance_dossier_run_path(move, run)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("insurance.run.title"))
    end

    it "shows a Turbo-bypassing Download link when the run is ready" do
      run = create(:insurance_dossier_run, :completed, move:)

      get move_insurance_dossier_run_path(move, run)

      # data-turbo=false or Turbo fetches the PDF into the void (the labels gotcha).
      expect(response.body).to include(I18n.t("insurance.status.download"))
      expect(response.body).to match(
        /<a [^>]*href="#{download_move_insurance_dossier_run_path(move, run)}"[^>]*data-turbo="false"/
      )
    end

    it "offers a retry when the run failed" do
      run = create(:insurance_dossier_run, :failed, move:)

      get move_insurance_dossier_run_path(move, run)

      expect(response.body).to include(I18n.t("insurance.status.failed_title"))
      expect(response.body).to include(I18n.t("insurance.status.retry"))
    end
  end

  describe "as a non-member (the relation-scope boundary on the most sensitive export)" do
    let(:outsider) { create(:user) }

    before { stub_current_user(outsider) }

    it "404s create, show and download" do
      run = create(:insurance_dossier_run, :completed, move:)

      post move_insurance_dossier_runs_path(move)
      expect(response).to have_http_status(:not_found)

      get move_insurance_dossier_run_path(move, run)
      expect(response).to have_http_status(:not_found)

      get download_move_insurance_dossier_run_path(move, run)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET .../runs/:id/download" do
    it "serves the attached PDF once ready" do
      run = create(:insurance_dossier_run, :completed, move:)

      get download_move_insurance_dossier_run_path(move, run)

      expect(response.content_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("attachment")
    end

    it "redirects back to the run page before the document is ready" do
      run = create(:insurance_dossier_run, :processing, move:)

      get download_move_insurance_dossier_run_path(move, run)

      expect(response).to redirect_to(move_insurance_dossier_run_path(move, run))
    end
  end
end
