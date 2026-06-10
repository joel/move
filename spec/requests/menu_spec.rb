# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Menu hub" do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin) } # creator → admin member

  before do
    stub_current_user(admin)
    stub_current_tenant("acme")
    allow(Apartment::Tenant).to receive(:current).and_return("acme")
  end

  describe "GET /moves/:move_id/menu" do
    it "renders the hub with the App and Organize groups for an admin" do
      get move_menu_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("menu.show.settings"))
      expect(response.body).to include(move_members_path(move))
      expect(response.body).to include(move_settings_path(move))
    end

    it "hides the admin-only Members link for a contributor" do
      contributor = create(:user)
      create(:move_membership, move:, user: contributor, role: "contributor")
      stub_current_user(contributor)

      get move_menu_path(move)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(move_members_path(move))
    end

    it "404s a non-member non-disclosingly" do
      stub_current_user(create(:user))

      get move_menu_path(move)

      expect(response).to have_http_status(:not_found)
    end
  end
end
