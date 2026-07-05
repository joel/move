# frozen_string_literal: true

require_relative "../../../script/self_healing/blast_radius"

RSpec.describe SelfHealing::BlastRadius do
  subject(:blast_radius) do
    described_class.new(
      deny: ["db/**", ".github/**", "Gemfile*", "packs/{organizations,accounts}/**", "sig/rbs_rails/**"],
      allow: ["app/actions/**", "spec/**", "packs/*/app/**", "sig/**"],
      size_limits: { "max_files" => 10, "max_non_spec_lines" => 200 }
    )
  end

  describe ".compile" do
    it "makes ** cross directory boundaries" do
      expect(described_class.compile("db/**")).to match("db/migrate/20260101000000_add_thing.rb")
    end

    it "keeps * within one path segment" do
      pattern = described_class.compile("packs/*/app/**")
      expect(pattern).to match("packs/labels/app/actions/labels/create.rb")
      expect(pattern).not_to match("packs/labels/nested/app/thing.rb")
    end

    it "expands {a,b} alternations" do
      pattern = described_class.compile("packs/{organizations,accounts}/**")
      expect(pattern).to match("packs/accounts/app/models/account.rb")
      expect(pattern).not_to match("packs/labels/app/models/label.rb")
    end

    it "does not let regexp metacharacters in patterns match literally-different paths" do
      expect(described_class.compile("Gemfile*")).not_to match("GemfileX/nested")
      expect(described_class.compile("a.b")).not_to match("aXb")
    end

    it "anchors the whole path" do
      expect(described_class.compile("db/**")).not_to match("app/db/thing.rb")
    end
  end

  describe "#allowed?" do
    it "permits a path matching allow and no deny" do
      expect(blast_radius.allowed?("app/actions/boxes/create.rb")).to be(true)
    end

    it "fails closed on a path matching no allow pattern" do
      expect(blast_radius.allowed?("app/misc/rodauth_main.rb")).to be(false)
    end

    it "lets deny win over allow" do
      expect(blast_radius.allowed?("sig/rbs_rails/app/models/box.rbs")).to be(false)
    end
  end

  describe "#violations" do
    it "names each offending path with its reason" do
      violations = blast_radius.violations(["db/migrate/x.rb", "app/unknown/y.rb", "spec/models/box_spec.rb"])
      expect(violations).to contain_exactly(
        { path: "db/migrate/x.rb", reason: "matches a deny pattern" },
        { path: "app/unknown/y.rb", reason: "matches no allow pattern (fail closed)" }
      )
    end
  end

  describe ".load" do
    subject(:real_config) { described_class.load }

    it "exposes the size limits" do
      expect(real_config.max_files).to eq(10)
      expect(real_config.max_non_spec_lines).to eq(200)
    end

    # Pin the load-bearing entries of the committed config: a config edit that
    # re-opens one of these surfaces must consciously change this spec too.
    it "denies migrations, the pipeline control plane, auth/tenancy packs, and client-side code" do
      denied = %w[
        db/migrate/20260101000000_x.rb
        config/initializers/sentry.rb
        .github/workflows/self-healing.yml
        script/self_healing/score.rb
        packs/accounts/app/models/account.rb
        app/misc/rodauth_main.rb
        app/javascript/controllers/poller_controller.js
        app/assets/tailwind/application.css
      ]
      expect(denied.select { |path| real_config.allowed?(path) }).to be_empty
    end

    it "allows the domain layers an autofix may touch" do
      allowed = %w[
        app/actions/boxes/create.rb
        app/models/box.rb
        app/views/boxes/index_view.rb
        packs/labels/app/actions/labels/create.rb
        spec/actions/boxes/create_spec.rb
        packs/labels/spec/actions/labels/create_spec.rb
      ]
      expect(allowed.reject { |path| real_config.allowed?(path) }).to be_empty
    end
  end
end
