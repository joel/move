require "rails_helper"

RSpec.describe "Welcomes" do
  describe "GET /home" do
    it "returns http success" do
      get "/welcome/home"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET / with a cross-host notice key (#844)" do
    let(:deleted_notice) { I18n.t("accounts.destroy.notice") }

    it "turns an allow-listed key into a flash and redirects to the clean URL" do
      get root_path(notice: "account_deleted")

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq(deleted_notice)
      follow_redirect!
      expect(response.body).to include(deleted_notice)
    end

    it "strips an unknown key without rendering it" do
      get root_path(notice: "<script>alert(1)</script> You won a prize")

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to be_nil
      follow_redirect!
      expect(response.body).not_to include("You won a prize")
    end

    it "ignores the key for a signed-in visitor (a deleted account is always signed out)" do
      stub_current_user(create(:user))

      get root_path(notice: "account_deleted")

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to be_nil
    end

    it "renders the plain page when no key is present" do
      get root_path
      expect(response).to have_http_status(:success)
      expect(flash[:notice]).to be_nil
    end
  end
end
