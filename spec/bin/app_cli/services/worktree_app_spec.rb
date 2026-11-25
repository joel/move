require "spec_helper"
require_relative "../../../../bin/cli-files/app-cmd/worktree_app"
require_relative "../../../../config/dev_worktree"

RSpec.describe AppCLI::Services::WorktreeApp do
  subject(:app) { described_class.new("fix-869") }

  it "derives the container, zone, apex and database from one label" do
    expect(app.container).to eq("move-app-wt-fix-869")
    expect(app.zone).to eq("fix-869.wt.move-easy.docker")
    expect(app.apex).to eq("move.fix-869.wt.move-easy.docker")
    expect(app.url).to eq("https://move.fix-869.wt.move-easy.docker")
    expect(app.database).to eq("move_development_wt_fix_869")
  end

  it "sets the env vars development.rb reads, with WEBAUTHN_RP_ID on the zone" do
    expect(app.env).to eq("MOVE_TENANT_ZONE" => "fix-869.wt.move-easy.docker",
                          "MOVE_DEV_DATABASE" => "move_development_wt_fix_869",
                          "WEBAUTHN_RP_ID" => "fix-869.wt.move-easy.docker")
    expect(app.env_flags).to include("--env MOVE_DEV_DATABASE=move_development_wt_fix_869")
  end

  it "makes a pair config/dev_worktree.rb accepts" do
    expect(DevWorktree.tenant_zone(app.env)).to eq(app.zone)
    expect(DevWorktree.database_for(app.label)).to eq(app.database)
  end

  describe ".for" do
    it "sanitises the checkout directory name" do
      expect(described_class.for(checkout_path: "/x/Move_WT.Foo--Bar").label).to eq("move-wt-foo-bar")
      expect(described_class.for(checkout_path: "/x/59a6025a").label).to eq("59a6025a")
    end

    it "cuts a long name to 20 characters without a trailing hyphen" do
      expect(described_class.for(checkout_path: "/x/abcdefghijklmnopqrs-tuvwxyz").label).to eq("abcdefghijklmnopqrs")
    end

    it "uses --name as given" do
      expect(described_class.for(checkout_path: "/x/anything", name: "demo").label).to eq("demo")
    end

    it "refuses a --name that is not a label instead of rewriting it" do
      ["Demo", "-a", "a-", "a.b", "a" * 21, ""].each do |name|
        expect { described_class.for(checkout_path: "/x/y", name: name) }.to raise_error(Thor::Error, /not a usable/)
      end
    end

    it "refuses a directory name with nothing usable in it" do
      expect { described_class.for(checkout_path: "/x/___") }.to raise_error(Thor::Error, /--name W/)
    end
  end
end
