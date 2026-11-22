# frozen_string_literal: true

require "yaml"
require "json"
require "open3"
require "tmpdir"
require "fileutils"

# Reads .github/workflows/self-healing.yml for the spec below.
module SelfHealingWorkflow
  ROOT = File.expand_path("../../..", __dir__)
  WORKFLOW = YAML.safe_load_file(File.join(ROOT, ".github/workflows/self-healing.yml")).freeze
  AGENT_ACTION = "anthropics/claude-code-action@"
  GIT_ENV = { "GIT_AUTHOR_NAME" => "t", "GIT_AUTHOR_EMAIL" => "t@example.com",
              "GIT_COMMITTER_NAME" => "t", "GIT_COMMITTER_EMAIL" => "t@example.com",
              "GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1" }.freeze

  def jobs = WORKFLOW.fetch("jobs")
  def job(name) = jobs.fetch(name)
  def uses_agent?(job) = job.fetch("steps").any? { |step| step["uses"].to_s.start_with?(AGENT_ACTION) }
  def agent_step = job("fix").fetch("steps").find { |step| step["uses"].to_s.start_with?(AGENT_ACTION) }

  def step_run(job_name, step_name)
    job(job_name).fetch("steps").find { |step| step["name"] == step_name }&.fetch("run") ||
      raise("no step #{step_name} in #{job_name}")
  end

  def writer_jobs
    jobs.select do |_name, job|
      perms = job["permissions"]
      (perms.is_a?(Hash) && perms.value?("write")) || job.to_yaml.include?("create-github-app-token")
    end
  end
end

# Pins the credential boundary of .github/workflows/self-healing.yml (#571):
# the job that runs model-generated code (claude-code-action + the specs the
# agent writes) holds no write-capable credential, and everything with write
# scope runs in a job that never executes the agent's output. Also runs the
# publish job's real validation script against sandbox git repositories.
RSpec.describe "Self-Healing workflow" do # rubocop:disable RSpec/DescribeClass
  include SelfHealingWorkflow

  describe "the job running model-generated code" do
    it "is only the fix job" do
      expect(jobs.select { |_name, job| uses_agent?(job) }.keys).to eq(["fix"])
    end

    it "has read-only permissions" do
      permissions = job("fix").fetch("permissions")

      expect(permissions).to eq("contents" => "read")
    end

    it "references no secret beyond the model API key and its read-only GITHUB_TOKEN" do
      secrets = job("fix").to_yaml.scan(/secrets\.([A-Z0-9_]+)/).flatten.uniq

      expect(secrets).to contain_exactly("AUTOFIX_ANTHROPIC_API_KEY", "GITHUB_TOKEN")
    end

    it "never mints the App token" do
      expect(job("fix").to_yaml).not_to include("create-github-app-token")
    end
  end

  describe "jobs holding write scope or the App token" do
    it "include the jobs that label, publish, score and merge" do
      expect(writer_jobs.keys).to include("prepare", "publish", "score", "steward")
    end

    it "never run the agent or execute repository code it may have written" do
      writer_jobs.each do |name, job|
        expect(uses_agent?(job)).to be(false), "#{name} runs claude-code-action"
        expect(job.to_yaml).not_to match(%r{bundle exec|bin/rails}), "#{name} executes app code"
      end
    end

    it "keeps the Sentry token out of the model job" do
      expect(job("fix").to_yaml).not_to include("SENTRY_AUTOFIX_TOKEN")
      expect(step_run("prepare", "Stage whitelist-reduced context per issue"))
        .to include("script/self_healing/sentry_fetch.rb event")
    end
  end

  describe "the autofix bot identity" do
    it "is a GitHub user id + login pair" do
      expect(SelfHealingWorkflow::WORKFLOW.fetch("env"))
        .to include("AUTOFIX_BOT_NAME" => "move-autofix[bot]", "AUTOFIX_BOT_ID" => match(/\A\d+\z/))
    end

    it "is passed to claude-code-action so its git setup keeps it" do
      expect(agent_step.fetch("with")).to include("bot_name" => "${{ env.AUTOFIX_BOT_NAME }}",
                                                  "bot_id" => "${{ env.AUTOFIX_BOT_ID }}")
    end

    it "is what the retry force-push guard accepts" do
      script = step_run("publish", "Push the fix branch and open the PR (App identity)")

      expect(script).to include('bot_email="${AUTOFIX_BOT_ID}+${AUTOFIX_BOT_NAME}@users.noreply.github.com"')
      expect(script).to include('if [ "$tip_author" != "$bot_email" ]; then')
    end
  end

  describe "publish: the assessment embedded in the PR body" do
    it "cannot close its HTML comment, and still round-trips through jq" do
      line = step_run("publish", "Push the fix branch and open the PR (App identity)")
             .lines.find { |l| l.include?('jq -c . "$ASSESSMENT"') }.strip
      assessment = { "confidence" => 80, "notes" => "--> <!-- hi --> a<b" }
      Dir.mktmpdir do |dir|
        path = File.join(dir, "assessment.json")
        File.write(path, JSON.generate(assessment))
        out, status = Open3.capture2e({ "ASSESSMENT" => path }, "bash", "-c", line)

        expect(status).to be_success
        expect(out).not_to include("-->")
        expect(JSON.parse(out)).to eq(assessment)
      end
    end
  end

  describe "publish: Validate the attempt" do
    def git(dir, *args)
      out, status = Open3.capture2e(SelfHealingWorkflow::GIT_ENV, "git", "-C", dir, *args)
      raise "git #{args.join(" ")} failed: #{out}" unless status.success?

      out
    end

    def commit_file(dir, path, content)
      FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
      File.write(File.join(dir, path), content)
      git(dir, "add", path)
      git(dir, "commit", "-q", "-m", "Change #{path}")
    end

    let(:tmp) { Dir.mktmpdir("self-healing-validate") }
    let(:upstream) { File.join(tmp, "upstream") }
    let(:attempt_dir) { File.join(tmp, "attempt") }
    let(:fix) { { "app/models/widget.rb" => "class Widget; end\n", "spec/models/widget_spec.rb" => "# spec\n" } }

    before do
      git(tmp, "init", "-q", "-b", "main", upstream)
      %w[script/self_healing/blast_radius.rb .github/autofix/blast_radius.yml].each do |path|
        commit_file(upstream, path, File.read(File.join(SelfHealingWorkflow::ROOT, path)))
      end
      FileUtils.mkdir_p(attempt_dir)
    end

    after { FileUtils.remove_entry(tmp) }

    # The fix job's side: commits on a clone, bundled exactly like the
    # "Package the attempt" step does.
    def agent_attempt(files:, assessment: { "confidence" => 80, "fixable" => true })
      agent = File.join(tmp, "agent")
      # Shallow, like the fix job's actions/checkout (depth 1).
      git(tmp, "clone", "-q", "--depth", "1", "file://#{upstream}", agent)
      files.each { |path, content| commit_file(agent, path, content) }
      bundle = File.join(attempt_dir, "fix.bundle")
      git(agent, "bundle", "create", "-q", bundle, "HEAD", "^origin/main") if files.any?
      File.write(File.join(attempt_dir, "assessment.json"), JSON.generate(assessment)) if assessment
      FileUtils.touch(File.join(attempt_dir, "packaged"))
    end

    def validate(download: "success", prepare: "success")
      judge = File.join(tmp, "judge")
      git(tmp, "clone", "-q", upstream, judge) unless Dir.exist?(judge)
      output = File.join(tmp, "github_output")
      File.write(output, "")
      env = SelfHealingWorkflow::GIT_ENV.merge(
        "GITHUB_OUTPUT" => output, "RUNNER_TEMP" => tmp, "ATTEMPT_DIR" => attempt_dir,
        "DOWNLOAD_OUTCOME" => download, "PREPARE_RESULT" => prepare
      )
      script = step_run("publish", "Validate the attempt")
      log, status = Open3.capture2e(env, "bash", "-c", script, chdir: judge)
      raise "validate crashed: #{log}" unless status.success?

      File.read(output)[/^result=(.*)$/, 1]
    end

    it "accepts commits on allowed paths with an assessment" do
      agent_attempt(files: fix)

      expect(validate).to eq("ok")
    end

    it "accepts the bundle after main has moved on" do
      agent_attempt(files: fix)
      commit_file(upstream, "app/models/other.rb", "class Other; end\n")

      expect(validate).to eq("ok")
    end

    it "rejects a deny-listed path before anything is pushed" do
      agent_attempt(files: fix.merge(".github/workflows/evil.yml" => "on: push\n"))

      expect(validate).to eq("deny-listed")
    end

    it "rejects a bundle built on an old main that would push stale denied files" do
      commit_file(upstream, ".github/workflows/ci.yml", "v1\n")
      old_main = git(upstream, "rev-parse", "HEAD").strip
      commit_file(upstream, ".github/workflows/ci.yml", "v2\n")
      agent = File.join(tmp, "agent")
      git(tmp, "clone", "-q", upstream, agent)
      git(agent, "checkout", "-q", old_main)
      fix.each { |path, content| commit_file(agent, path, content) }
      git(agent, "bundle", "create", "-q", File.join(attempt_dir, "fix.bundle"), "HEAD", "^#{old_main}")
      File.write(File.join(attempt_dir, "assessment.json"), JSON.generate("confidence" => 80, "fixable" => true))
      FileUtils.touch(File.join(attempt_dir, "packaged"))

      expect(validate).to eq("deny-listed")
    end

    it "reports a fix leg that produced no artifact" do
      expect(validate(download: "failure")).to eq("agent-step-failed")
    end

    it "reports a failed prepare job" do
      expect(validate(prepare: "failure")).to eq("prepare-failed")
    end

    it "reports an attempt without commits" do
      agent_attempt(files: {})

      expect(validate).to eq("no-commits")
    end

    it "rejects a corrupt bundle" do
      agent_attempt(files: {})
      File.write(File.join(attempt_dir, "fix.bundle"), "not a bundle")

      expect(validate).to eq("bundle-invalid")
    end

    it "requires a well-formed assessment" do
      agent_attempt(files: fix, assessment: nil)

      expect(validate).to eq("no-assessment")
    end

    it "honours a not-fixable self-assessment" do
      agent_attempt(files: fix, assessment: { "confidence" => 20, "fixable" => false })

      expect(validate).to eq("not-fixable")
    end
  end
end
