require "rails_helper"

RSpec.describe "WelcomeController" do
  describe "routing" do
    it "routes to #home" do
      expect(get: "/welcome/home").to route_to("welcome#home")
    end
  end
end
