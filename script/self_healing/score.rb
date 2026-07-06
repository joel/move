# frozen_string_literal: true

require "json"
require_relative "blast_radius"
require_relative "diff_stats"

module SelfHealing
  # Deterministic confidence/safety engine for autofix PRs
  # (doc/project/self-healing.md). Given the PR's changed files, diff, commit
  # messages, title/body, and the agent's self-assessment, it applies hard
  # gates and a weighted score and returns the autonomy verdict:
  #
  #   auto-eligible  — no gate failed, S >= THRESHOLD and C_agent >= MIN_AGENT
  #   needs-human    — anything else (fail closed)
  #
  # The workflow always executes this file from a checkout of main, so a PR
  # cannot rewrite its own judge. Weights and thresholds are tested constants
  # (spec/script/self_healing/score_spec.rb) — tune them there, deliberately,
  # after calibration runs.
  class Score
    WEIGHTS = { agent: 0.45, size: 0.25, spec_quality: 0.20, locality: 0.10 }.freeze
    THRESHOLD = 85
    MIN_AGENT_CONFIDENCE = 70
    # Lines (non-spec, additions+deletions) at or under which size scores 100;
    # it then falls linearly to 0 at the blast-radius max_non_spec_lines cap.
    FULL_MARKS_LINES = 20

    # Replicates the local-only ForbidSkipMarkers overcommit hook as a
    # SUPERSET: space *and hyphen* separators with optional padding, plus the
    # GitHub-honoured `skip-checks: true` trailer. A squash merge quoting
    # `[skip deploy]` silently skips the deploy, and the GitHub platform-level
    # `[skip ci]` family (hyphenated forms included) suppresses ALL workflows
    # (AGENTS.md §4) — so a marker anywhere in what could reach the squash
    # commit message is a hard gate, not a style nit. Keep in sync with
    # .git-hooks/commit_msg/forbid_skip_markers.rb.
    SKIP_MARKERS = Regexp.union(
      /\[\s*(?:skip[\s-]+(?:ci|actions|deploy)|(?:ci|actions)[\s-]+skip|no[\s-]+ci)\s*\]/i,
      /skip-checks:\s*true/i
    )

    # The local FixMe overcommit hook blocks this token at commit time, but a
    # bot commit is made in CI where hooks never run and no cop covers it.
    # (Built without the literal so the hook doesn't trip on this file.)
    FIXME_TOKEN = /\bFIXME\b/

    #: (input: Hash[String, untyped], blast_radius: BlastRadius) -> void
    def initialize(input:, blast_radius:)
      @input = input
      @blast_radius = blast_radius
      @diff_stats = DiffStats.new(input.fetch("diff", ""))
    end

    #: () -> Hash[Symbol, untyped]
    def verdict
      failures = gate_failures
      score = failures.empty? ? weighted_score : nil
      {
        verdict: verdict_label(failures, score),
        score: score,
        components: failures.empty? ? components : nil,
        gate_failures: failures,
        # Echo the tuning constants so the PR audit-trail comment renders the
        # numbers that actually judged this PR, never a stale copy.
        thresholds: { score: THRESHOLD, agent_confidence: MIN_AGENT_CONFIDENCE },
        weights: WEIGHTS
      }
    end

    #: () -> Array[String]
    def gate_failures
      @gate_failures ||= [
        blast_radius_failure,
        size_failure,
        spec_evidence_failure,
        skip_marker_failure,
        fixme_failure,
        assessment_failure,
        tdd_evidence_failure
      ].compact
    end

    #: () -> Hash[Symbol, Numeric]
    def components
      {
        agent: agent_confidence,
        size: size_score,
        spec_quality: spec_quality_score,
        locality: locality_score
      }
    end

    #: () -> Float
    def weighted_score
      components.sum { |name, value| WEIGHTS.fetch(name) * value }.round(1)
    end

    private

    #: (Array[String] failures, Float? score) -> String
    def verdict_label(failures, score)
      if failures.empty? && score >= THRESHOLD && agent_confidence >= MIN_AGENT_CONFIDENCE
        "auto-eligible"
      else
        "needs-human"
      end
    end

    #: () -> Array[Hash[String, untyped]]
    def files = @input.fetch("files")

    #: () -> Array[String]
    def paths = files.map { |file| file.fetch("path") }

    # Blast radius judges BOTH sides of a rename: a file moved out of a denied
    # path (e.g. script/** -> app/models/foo.rb) exposes the denied source only
    # via previous_path, and removing a denied file is as much a control-plane
    # change as editing it.
    #: () -> Array[String]
    def blast_paths = paths + files.filter_map { |file| file["previous_path"] }

    #: () -> Array[String]
    def non_spec_paths = paths.reject { |path| DiffStats.spec_path?(path) }

    #: () -> Integer
    def non_spec_lines
      files.reject { |file| DiffStats.spec_path?(file.fetch("path")) }
           .sum { |file| file.fetch("additions") + file.fetch("deletions") }
    end

    #: () -> String?
    def blast_radius_failure
      violations = @blast_radius.violations(blast_paths)
      return if violations.empty?

      details = violations.map { |violation| "#{violation[:path]} (#{violation[:reason]})" }
      "blast radius: #{details.join(", ")}"
    end

    #: () -> String?
    def size_failure
      if files.size > @blast_radius.max_files
        "size: #{files.size} files changed (max #{@blast_radius.max_files})"
      elsif non_spec_lines > @blast_radius.max_non_spec_lines
        "size: #{non_spec_lines} non-spec lines changed (max #{@blast_radius.max_non_spec_lines})"
      end
    end

    #: () -> String?
    def spec_evidence_failure
      # A spec-only diff fixes nothing (and would falsely mark the Sentry
      # issue resolved) — an error fix must change production code, and its
      # spec evidence must accompany a production change, not replace it.
      return "spec evidence: no production change (spec-only diff)" if non_spec_paths.empty?
      return "spec evidence: no spec file changed" if paths.none? { |path| DiffStats.spec_path?(path) }
      return "spec evidence: no added example (it/specify/scenario)" if @diff_stats.added_spec_examples.zero?
      # An example with no expectation is not regression evidence — without
      # this gate an empty `it` block plus max confidence could clear the
      # autonomy threshold.
      return "spec evidence: no added expectation (expect)" if @diff_stats.added_spec_expectations.zero?

      nil
    end

    #: () -> String?
    def skip_marker_failure
      texts = [@input.fetch("pr_title", ""), @input.fetch("pr_body", ""), *@input.fetch("commit_messages", [])]
      return unless texts.any? { |text| text.to_s.match?(SKIP_MARKERS) }

      "skip marker: a [skip ci]/[skip deploy]-style marker would suppress CI or the deploy on merge"
    end

    #: () -> String?
    def fixme_failure
      offending = paths.select { |path| @diff_stats.added_lines(path).any? { |line| line.match?(FIXME_TOKEN) } }
      return if offending.empty?

      "fixme: added FIXME token in #{offending.join(", ")}"
    end

    #: () -> String?
    def assessment_failure
      assessment = @input["assessment"]
      return "assessment: missing" unless assessment.is_a?(Hash)

      confidence = assessment["confidence"]
      return "assessment: confidence must be an integer 0..100" unless confidence.is_a?(Integer) && (0..100).cover?(confidence)
      return "assessment: diagnosis missing" unless assessment["diagnosis"].is_a?(String) && !assessment["diagnosis"].strip.empty?

      nil
    end

    # TDD evidence is a hard requirement for autonomy, not workflow-side
    # courtesy: a guessed fix with a token spec line must never reach the
    # steward. The agent must claim, in the assessment it signs, that the
    # regression spec existed AND failed before the fix.
    #: () -> String?
    def tdd_evidence_failure
      assessment = @input["assessment"]
      return unless assessment.is_a?(Hash) # absence is assessment_failure's gate

      return "assessment: fixable is not true" unless assessment["fixable"] == true
      return "assessment: spec_file missing" unless assessment["spec_file"].is_a?(String) && !assessment["spec_file"].strip.empty?
      return "assessment: spec_failed_before_fix is not true" unless assessment["spec_failed_before_fix"] == true

      nil
    end

    #: () -> Integer
    def agent_confidence
      assessment = @input["assessment"]
      assessment.is_a?(Hash) && assessment["confidence"].is_a?(Integer) ? assessment["confidence"].clamp(0, 100) : 0
    end

    #: () -> Numeric
    def size_score
      max = @blast_radius.max_non_spec_lines
      return 100 if non_spec_lines <= FULL_MARKS_LINES

      (100.0 * (max - non_spec_lines) / (max - FULL_MARKS_LINES)).round.clamp(0, 100)
    end

    # The spec-evidence hard gate guarantees at least one example WITH an
    # expectation by the time this scores, so quality only grades example
    # count.
    #: () -> Integer
    def spec_quality_score
      (70 + (10 * (@diff_stats.added_spec_examples - 1))).clamp(70, 100)
    end

    # Tighter fixes score higher: one production file is ideal; one directory
    # is close; one top-level area is acceptable; a scatter is suspect.
    #: () -> Integer
    def locality_score
      return 100 if non_spec_paths.size <= 1
      return 80 if non_spec_paths.map { |path| File.dirname(path) }.uniq.size == 1
      return 60 if non_spec_paths.map { |path| path.split("/").first(2) }.uniq.size == 1

      40
    end
  end
end

if $PROGRAM_NAME == __FILE__
  input_path = ARGV[0]
  abort "usage: score.rb INPUT_JSON" unless input_path

  score = SelfHealing::Score.new(
    input: JSON.parse(File.read(input_path)),
    # Always the config from the checked-out (main) tree. Deliberately NO
    # override flag: a caller must never be able to point the judge at a
    # PR-controlled blast-radius config.
    blast_radius: SelfHealing::BlastRadius.load(SelfHealing::BlastRadius::DEFAULT_CONFIG_PATH)
  )
  puts JSON.pretty_generate(score.verdict)
end
