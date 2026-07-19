# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Insurance declaration" do
  include PdfHelpers

  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  describe "GET /moves/:move_id/insurance/declaration" do
    it "serves the PDF inline and emits the audit event" do
      box = create(:box, move:, number: "1")
      create(:item, :manual, move:, box:, name: "Mug")
      allow(Rails.event).to receive(:notify)

      get move_insurance_declaration_path(move)

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq("application/pdf")
        expect(response.headers["Content-Disposition"]).to include("inline")
        expect(Rails.event).to have_received(:notify).with(
          "insurance.declaration_generated", move_id: move.id, actor_id: user.id, item_count: 1
        )
      end
    end

    # #702 — THE privacy invariant: the declaration must never reveal where an
    # item is packed. Fixture names are deliberately word-clean (no item name
    # contains "Box"/"Room"/the room name) so the whole-document assertions on
    # the exact forbidden strings cannot false-negative.
    it "contains no box numbers and no room names anywhere in the document" do
      room = create(:room, move:, name: "Master Bedroom")
      box = create(:box, move:, number: "7", room: room)
      create(:item, :manual, move:, box:, name: "Gold ring", family: "jewellery")
      create(:item, :manual, move:, box:, name: "Silver necklace")

      get move_insurance_declaration_path(move)

      text = document_text(response.body)
      aggregate_failures do
        expect(text).to include("Gold ring").and include("Jewellery")
        expect(text).not_to include("Box")
        expect(text).not_to include("007")
        expect(text).not_to include("Master Bedroom")
        expect(text).not_to include("Room")
      end
    end

    it "is open to a viewer member (sanitized by design — manifest parity)" do
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      get move_insurance_declaration_path(move)

      expect(response).to have_http_status(:ok)
    end

    it "404s for a non-member" do
      outsider = create(:user)
      stub_current_user(outsider)

      get move_insurance_declaration_path(move)

      expect(response).to have_http_status(:not_found)
    end

    it "redirects to the hub with an alert when distinct lines exceed the sync-render cap" do
      box = create(:box, move:, number: "1")
      create(:item, :manual, move:, box:, name: "Mug")
      stub_const("InsuranceDeclarations::Generate::MAX_LINES", 0)

      get move_insurance_declaration_path(move)

      expect(response).to redirect_to(move_insurance_path(move))
      expect(flash[:alert]).to eq(I18n.t("insurance.errors.too_many_lines", max: 0))
    end
  end

  describe "GET /moves/:move_id/insurance (hub)" do
    it "renders both cards for an admin" do
      box = create(:box, move:, number: "1")
      create(:item, :manual, move:, box:, name: "Mug")

      get move_insurance_path(move)

      expect(response.body).to include(I18n.t("insurance.declaration.title"))
      expect(response.body).to include(I18n.t("insurance.dossier.title"))
    end

    it "renders the empty state instead of export cards when nothing is packed" do
      get move_insurance_path(move)

      expect(response.body).to include(I18n.t("insurance.empty.title"))
      expect(response.body).not_to include(I18n.t("insurance.declaration.download"))
    end

    it "hides the dossier card from a viewer (no dead-end 403)" do
      box = create(:box, move:, number: "1")
      create(:item, :manual, move:, box:, name: "Mug")
      viewer = create(:user)
      create(:move_membership, move:, user: viewer, role: "viewer")
      stub_current_user(viewer)

      get move_insurance_path(move)

      expect(response.body).to include(I18n.t("insurance.declaration.title"))
      expect(response.body).not_to include(I18n.t("insurance.dossier.title"))
    end
  end
end
