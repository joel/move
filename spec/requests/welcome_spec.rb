require "rails_helper"

RSpec.describe "Welcomes" do
  describe "GET /home" do
    it "returns http success" do
      get "/welcome/home"
      expect(response).to have_http_status(:success)
    end
  end
end
