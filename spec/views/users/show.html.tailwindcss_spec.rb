require "rails_helper"

RSpec.describe "users/show" do
  before do
    assign(:user, User.create!(
                    name: "Name"
                  ))
  end

  it "renders attributes in <p>" do
    render
    expect(rendered).to match(/Name/)
  end
end
