require "rails_helper"

RSpec.describe "Moves" do
  let(:user) { create(:user) }

  before do
    stub_current_user(user)
    # Pretend we are on an Organization subdomain (the elevator does this in
    # real requests); Move data resolves against the public template here.
    stub_current_tenant("acme")
  end

  describe "GET /moves" do
    it "renders the list of moves" do
      create(:move, name: "Lake House", created_by: user)

      get moves_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lake House").and include("Your moves")
    end

    it "renders the empty state when there are no moves" do
      get moves_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("moves.empty.title"))
    end
  end

  describe "GET /moves/new" do
    it "renders the create form" do
      get new_move_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("moves.form.name"))
    end
  end

  describe "POST /moves" do
    it "creates a move and redirects to the list" do
      expect do
        post moves_path, params: { move: { name: "Beach House", unit_system: "imperial" } }
      end.to change(Move, :count).by(1)

      expect(response).to redirect_to(moves_path)
      expect(Move.find_by(name: "Beach House").move_memberships.find_by(user: user).role).to eq("admin")
    end

    it "re-renders the form with errors for an invalid move" do
      expect do
        post moves_path, params: { move: { name: "", unit_system: "metric" } }
      end.not_to change(Move, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /moves while the sample is provisioning (#432)" do
    it "renders the live placeholder + a stream subscription when the org is provisioning" do
      create(:organization, slug: "acme", demo_data_status: "provisioning")

      get moves_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("moves.sample.preparing"))
                           .and include("turbo-cable-stream-source")
    end

    it "renders a fallback card when provisioning failed" do
      create(:organization, slug: "acme", demo_data_status: "failed")

      get moves_path

      expect(response).to have_http_status(:ok)
      # Title carries an apostrophe Phlex HTML-escapes; match an unescaped fragment.
      expect(response.body).to include("set up your sample move")
    end

    it "shows the list (not the placeholder) once the user has a Move" do
      create(:organization, slug: "acme", demo_data_status: "provisioning")
      create(:move, name: "Lake House", created_by: user)

      get moves_path

      expect(response.body).to include("Lake House")
      expect(response.body).not_to include(I18n.t("moves.sample.preparing"))
    end
  end

  describe "DELETE /moves/:id (#432)" do
    it "lets an admin remove the sample Move" do
      move = create(:move, created_by: user, sample: true)

      expect { delete move_path(move) }.to change(Move, :count).by(-1)
      expect(response).to redirect_to(moves_path)
    end

    it "forbids a non-admin (viewer) from removing a Move" do
      owner = create(:user)
      move = create(:move, created_by: owner)
      move.move_memberships.create!(user: user, role: "viewer")

      delete move_path(move)

      expect(response).to have_http_status(:forbidden)
      expect(Move.exists?(move.id)).to be(true)
    end

    it "shows the Remove affordance to an admin of the sample Move" do
      create(:move, name: "Mine", created_by: user, sample: true)

      get moves_path

      expect(response.body).to include(I18n.t("moves.sample.remove"))
    end

    it "hides the Remove affordance from a non-admin member of a sample Move" do
      owner = create(:user)
      move = create(:move, name: "Shared sample", created_by: owner, sample: true)
      move.move_memberships.create!(user: user, role: "viewer")

      get moves_path

      expect(response.body).to include("Shared sample")
      expect(response.body).not_to include(I18n.t("moves.sample.remove"))
    end
  end

  describe "without a tenant (apex/public)" do
    it "returns 404 (non-disclosing)" do
      stub_current_tenant(nil)

      get moves_path

      expect(response).to have_http_status(:not_found)
    end
  end
end
