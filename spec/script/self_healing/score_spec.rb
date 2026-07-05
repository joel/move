# frozen_string_literal: true

require_relative "../../../script/self_healing/score"

RSpec.describe SelfHealing::Score do
  # Mirrors the committed .github/autofix/blast_radius.yml limits without
  # coupling every example to the full production pattern list.
  let(:blast_radius) do
    SelfHealing::BlastRadius.new(
      deny: ["db/**", ".github/**", "script/**"],
      allow: ["app/**", "spec/**", "packs/*/app/**", "packs/*/spec/**"],
      size_limits: { "max_files" => 10, "max_non_spec_lines" => 200 }
    )
  end

  def spec_diff(examples: 1, expectations: 1)
    lines = Array.new(examples) { |i| "+  it \"case #{i}\" do" } +
            Array.new(expectations) { "+    expect(result).to be_success" }
    <<~DIFF
      diff --git a/spec/actions/boxes/create_spec.rb b/spec/actions/boxes/create_spec.rb
      --- a/spec/actions/boxes/create_spec.rb
      +++ b/spec/actions/boxes/create_spec.rb
      @@ -1,1 +1,9 @@
      #{lines.join("\n")}
    DIFF
  end

  def input_for(overrides = {})
    {
      "files" => [
        { "path" => "app/actions/boxes/create.rb", "additions" => 3, "deletions" => 2 },
        { "path" => "spec/actions/boxes/create_spec.rb", "additions" => 8, "deletions" => 0 }
      ],
      "diff" => spec_diff,
      "commit_messages" => ["Fix box numbering beyond ten (#600)"],
      "pr_title" => "Fix box numbering beyond ten",
      "pr_body" => "Closes #600",
      "assessment" => { "confidence" => 90, "diagnosis" => "lexical MAX on a text column" }
    }.merge(overrides)
  end

  def verdict_for(overrides = {})
    described_class.new(input: input_for(overrides), blast_radius: blast_radius).verdict
  end

  describe "the weighted score" do
    it "pins the weights and the baseline arithmetic" do
      verdict = verdict_for
      expect(verdict[:components]).to eq(agent: 90, size: 100, spec_quality: 70, locality: 100)
      expect(verdict[:score]).to eq(89.5)
      expect(verdict[:verdict]).to eq("auto-eligible")
    end

    it "is auto-eligible exactly at the 85 threshold" do
      verdict = verdict_for("assessment" => { "confidence" => 80, "diagnosis" => "d" })
      expect(verdict[:score]).to eq(85.0)
      expect(verdict[:verdict]).to eq("auto-eligible")
    end

    it "needs a human just under the threshold" do
      verdict = verdict_for("assessment" => { "confidence" => 79, "diagnosis" => "d" })
      expect(verdict[:score]).to eq(84.6)
      expect(verdict[:verdict]).to eq("needs-human")
    end

    it "needs a human when agent confidence is under 70 even with a high score" do
      verdict = verdict_for(
        "assessment" => { "confidence" => 69, "diagnosis" => "d" },
        "diff" => spec_diff(examples: 4, expectations: 4)
      )
      expect(verdict[:score]).to be >= described_class::THRESHOLD
      expect(verdict[:verdict]).to eq("needs-human")
    end

    it "echoes the tuning constants so the audit-trail comment can never go stale" do
      verdict = verdict_for
      expect(verdict[:thresholds]).to eq(score: 85, agent_confidence: 70)
      expect(verdict[:weights]).to eq(agent: 0.45, size: 0.25, spec_quality: 0.20, locality: 0.10)
    end
  end

  describe "the size component" do
    def with_non_spec_lines(lines)
      verdict_for(
        "files" => [
          { "path" => "app/actions/boxes/create.rb", "additions" => lines, "deletions" => 0 },
          { "path" => "spec/actions/boxes/create_spec.rb", "additions" => 8, "deletions" => 0 }
        ]
      )
    end

    it "scores 100 at 20 non-spec lines, 50 midway, 0 at the cap" do
      expect(with_non_spec_lines(20)[:components][:size]).to eq(100)
      expect(with_non_spec_lines(110)[:components][:size]).to eq(50)
      expect(with_non_spec_lines(200)[:components][:size]).to eq(0)
    end
  end

  describe "the spec-quality component" do
    it "scores 30 without expectations, then 70/80/100 by example count" do
      expect(verdict_for("diff" => spec_diff(expectations: 0))[:components][:spec_quality]).to eq(30)
      expect(verdict_for("diff" => spec_diff(examples: 1))[:components][:spec_quality]).to eq(70)
      expect(verdict_for("diff" => spec_diff(examples: 2))[:components][:spec_quality]).to eq(80)
      expect(verdict_for("diff" => spec_diff(examples: 5))[:components][:spec_quality]).to eq(100)
    end
  end

  describe "the locality component" do
    def with_production_files(*paths)
      files = paths.map { |path| { "path" => path, "additions" => 2, "deletions" => 0 } }
      files << { "path" => "spec/actions/boxes/create_spec.rb", "additions" => 8, "deletions" => 0 }
      verdict_for("files" => files)[:components][:locality]
    end

    it "rewards tight changes and penalises scatter" do
      expect(with_production_files("app/actions/boxes/create.rb")).to eq(100)
      expect(with_production_files("app/actions/boxes/create.rb", "app/actions/boxes/update.rb")).to eq(80)
      expect(with_production_files("app/actions/boxes/create.rb", "app/actions/items/create.rb")).to eq(60)
      expect(with_production_files("app/actions/boxes/create.rb", "app/models/box.rb")).to eq(40)
    end
  end

  describe "hard gates" do
    it "gates a deny-listed path and reports no score" do
      verdict = verdict_for(
        "files" => [
          { "path" => "db/migrate/20260101000000_x.rb", "additions" => 3, "deletions" => 0 },
          { "path" => "spec/actions/boxes/create_spec.rb", "additions" => 8, "deletions" => 0 }
        ]
      )
      expect(verdict[:verdict]).to eq("needs-human")
      expect(verdict[:score]).to be_nil
      expect(verdict[:gate_failures].join).to include("db/migrate")
    end

    it "gates a path outside the allow list (fail closed)" do
      verdict = verdict_for(
        "files" => [
          { "path" => "Dockerfile", "additions" => 1, "deletions" => 0 },
          { "path" => "spec/actions/boxes/create_spec.rb", "additions" => 8, "deletions" => 0 }
        ]
      )
      expect(verdict[:gate_failures].join).to include("fail closed")
    end

    it "gates a PR without a spec change" do
      verdict = verdict_for(
        "files" => [{ "path" => "app/actions/boxes/create.rb", "additions" => 3, "deletions" => 2 }],
        "diff" => ""
      )
      expect(verdict[:gate_failures].join).to include("no spec file changed")
    end

    it "gates a spec change that adds no example" do
      verdict = verdict_for("diff" => spec_diff(examples: 0))
      expect(verdict[:gate_failures].join).to include("no added example")
    end

    it "gates skip markers wherever they could reach the squash commit message" do
      ["[skip ci]", "[CI SKIP]", "[skip deploy]", "[no ci]", "[skip actions]"].each do |marker|
        expect(verdict_for("pr_title" => "Fix #{marker}")[:gate_failures].join).to include("skip marker")
      end
      expect(verdict_for("pr_body" => "quotes [skip deploy]")[:gate_failures].join).to include("skip marker")
      expect(verdict_for("commit_messages" => ["ok", "b [ci skip]"])[:gate_failures].join).to include("skip marker")
    end

    it "gates the hyphenated marker forms and the skip-checks trailer the hook also rejects" do
      ["[skip-ci]", "[ci-skip]", "[no-ci]", "[skip-actions]", "[actions-skip]", "[skip-deploy]"].each do |marker|
        expect(verdict_for("pr_title" => "Fix #{marker}")[:gate_failures].join).to include("skip marker")
      end
      expect(verdict_for("pr_body" => "Done.\n\nskip-checks: true")[:gate_failures].join).to include("skip marker")
      expect(verdict_for("commit_messages" => ["ok", "b\n\nskip-checks:  TRUE"])[:gate_failures].join)
        .to include("skip marker")
    end

    it "gates an added FIX-ME token (the local hook cannot cover bot commits)" do
      token = "FIXME"
      diff = spec_diff + <<~DIFF
        diff --git a/app/actions/boxes/create.rb b/app/actions/boxes/create.rb
        --- a/app/actions/boxes/create.rb
        +++ b/app/actions/boxes/create.rb
        @@ -1,1 +1,2 @@
        +  # #{token}: revisit after the incident
      DIFF
      verdict = verdict_for("diff" => diff)
      expect(verdict[:gate_failures].join).to include("fixme")
      expect(verdict[:gate_failures].join).to include("app/actions/boxes/create.rb")
    end

    it "gates a missing or malformed assessment" do
      expect(verdict_for("assessment" => nil)[:gate_failures].join).to include("assessment: missing")
      expect(verdict_for("assessment" => { "confidence" => "90", "diagnosis" => "d" })[:gate_failures].join)
        .to include("confidence")
      expect(verdict_for("assessment" => { "confidence" => 101, "diagnosis" => "d" })[:gate_failures].join)
        .to include("confidence")
      expect(verdict_for("assessment" => { "confidence" => 90, "diagnosis" => " " })[:gate_failures].join)
        .to include("diagnosis")
    end

    it "gates oversized changes by file count and by non-spec line count" do
      many_files = Array.new(11) { |i| { "path" => "app/actions/boxes/a#{i}.rb", "additions" => 1, "deletions" => 0 } }
      expect(verdict_for("files" => many_files)[:gate_failures].join).to include("11 files")

      fat = [
        { "path" => "app/actions/boxes/create.rb", "additions" => 201, "deletions" => 0 },
        { "path" => "spec/actions/boxes/create_spec.rb", "additions" => 8, "deletions" => 0 }
      ]
      expect(verdict_for("files" => fat)[:gate_failures].join).to include("201 non-spec lines")
    end

    it "never counts spec lines against the size cap" do
      verdict = verdict_for(
        "files" => [
          { "path" => "app/actions/boxes/create.rb", "additions" => 3, "deletions" => 2 },
          { "path" => "spec/actions/boxes/create_spec.rb", "additions" => 500, "deletions" => 0 }
        ]
      )
      expect(verdict[:gate_failures]).to be_empty
    end
  end
end
