# frozen_string_literal: true

require "spec_helper"
require "erb"
require "yaml"
require_relative "../../config/dev_worktree"

# #869: `bin/cli app serve` points a worktree app at its own zone and dev
# database through MOVE_TENANT_ZONE and MOVE_DEV_DATABASE. Only development
# reads them; production and test must not change.
RSpec.describe DevWorktree do
  let(:pair) { { "MOVE_TENANT_ZONE" => "w-1.wt.move-easy.docker", "MOVE_DEV_DATABASE" => "move_development_wt_w_1" } }

  describe ".tenant_zone" do
    it "is main's zone when neither variable is set" do
      expect(described_class.tenant_zone({})).to eq("move-easy.docker")
      expect(described_class.apex_host({})).to eq("move.move-easy.docker")
      expect(described_class.tenant_zone("MOVE_TENANT_ZONE" => "", "MOVE_DEV_DATABASE" => "")).to eq("move-easy.docker")
    end

    it "is the worktree zone for a matching pair" do
      expect(described_class.tenant_zone(pair)).to eq("w-1.wt.move-easy.docker")
      expect(described_class.apex_host(pair)).to eq("move.w-1.wt.move-easy.docker")
    end

    it "refuses a zone outside wt.move-easy.docker" do
      ["move-easy.docker", "evil.com", "a.b.wt.move-easy.docker", "wt.move-easy.docker"].each do |zone|
        expect { described_class.tenant_zone(pair.merge("MOVE_TENANT_ZONE" => zone)) }
          .to raise_error(described_class::Error, /MOVE_TENANT_ZONE/)
      end
    end

    it "refuses a database that is not the zone's own, main's included" do
      %w[move_development move_development_wt_other].each do |database|
        expect { described_class.tenant_zone(pair.merge("MOVE_DEV_DATABASE" => database)) }
          .to raise_error(described_class::Error, /must be move_development_wt_w_1/)
      end
    end

    it "refuses one variable without the other" do
      expect { described_class.tenant_zone(pair.except("MOVE_DEV_DATABASE")) }.to raise_error(described_class::Error)
      expect { described_class.tenant_zone(pair.except("MOVE_TENANT_ZONE")) }.to raise_error(described_class::Error)
    end
  end

  describe ".assert_database!" do
    it "does nothing for main" do
      expect { described_class.assert_database!("move_development", {}) }.not_to raise_error
    end

    it "accepts the worktree's own database" do
      expect { described_class.assert_database!("move_development_wt_w_1", pair) }.not_to raise_error
    end

    it "refuses any other resolved database, as a DATABASE_URL would give" do
      ["move_development", "other", nil].each do |resolved|
        expect { described_class.assert_database!(resolved, pair) }
          .to raise_error(described_class::Error, /Refusing to boot/)
      end
    end
  end

  describe "the config files" do
    let(:root) { File.expand_path("../..", __dir__) }

    def database_yml(env)
      original = ENV.to_h
      ENV.update(env)
      YAML.safe_load(ERB.new(File.read(File.join(root, "config/database.yml"))).result, aliases: true)
    ensure
      ENV.replace(original)
    end

    it "points only the development database at MOVE_DEV_DATABASE" do
      main = database_yml("MOVE_DEV_DATABASE" => "")
      worktree = database_yml(pair)

      expect(main.dig("development", "database")).to eq("move_development")
      expect(worktree.dig("development", "database")).to eq("move_development_wt_w_1")
      expect(worktree["test"]).to eq(main["test"])
      expect(worktree["production"]).to eq(main["production"])
      expect(worktree.dig("production", "primary", "database")).to eq("move_production")
    end

    it "keeps the overrides out of production and test" do
      %w[production test].each do |env|
        source = File.read(File.join(root, "config/environments/#{env}.rb"))
        expect(source).not_to match(/MOVE_TENANT_ZONE|MOVE_DEV_DATABASE|DevWorktree|dev_worktree/)
      end
      expect(File.read(File.join(root, "config/environments/development.rb"))).to include('require_relative "../dev_worktree"')
    end
  end
end
