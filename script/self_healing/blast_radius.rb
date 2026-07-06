# frozen_string_literal: true

require "yaml"

module SelfHealing
  # Path-level blast-radius policy for autofix PRs, loaded from
  # .github/autofix/blast_radius.yml (always the copy on main — the workflow
  # never checks this file out from the PR head, and .github/** is itself
  # deny-listed, so a PR cannot widen its own blast radius).
  #
  # Fail-closed semantics: a path is permitted only when it matches at least
  # one allow pattern and no deny pattern; deny wins over allow; anything
  # matching neither list is denied.
  class BlastRadius
    DEFAULT_CONFIG_PATH = File.expand_path("../../.github/autofix/blast_radius.yml", __dir__)

    #: (Array[String] deny, Array[String] allow, Hash[String, Integer] size_limits) -> void
    def initialize(deny:, allow:, size_limits:)
      @deny = deny.map { |pattern| self.class.compile(pattern) }
      @allow = allow.map { |pattern| self.class.compile(pattern) }
      @size_limits = size_limits
    end

    #: (?String path) -> BlastRadius
    def self.load(path = DEFAULT_CONFIG_PATH)
      config = YAML.safe_load_file(path)
      new(
        deny: config.fetch("deny"),
        allow: config.fetch("allow"),
        size_limits: config.fetch("size_limits")
      )
    end

    # Compile one .gitignore-style glob into an anchored Regexp: `**` crosses
    # directory boundaries, `*`/`?` stay within a segment, `{a,b}` alternates.
    # (File.fnmatch's `**` handling under FNM_PATHNAME only special-cases the
    # exact `**/` form, which silently breaks patterns like `db/**` — hence a
    # hand-rolled translation with specs pinning the semantics.)
    #: (String pattern) -> Regexp
    def self.compile(pattern)
      source = pattern.gsub(/\*\*|[*?{},]|[^*?{},]+/) do |token|
        case token
        when "**" then ".*"
        when "*" then "[^/]*"
        when "?" then "[^/]"
        when "{" then "(?:"
        when "}" then ")"
        when "," then "|"
        else Regexp.escape(token)
        end
      end
      /\A#{source}\z/
    end

    #: (String path) -> bool
    def denied?(path)
      @deny.any? { |pattern| pattern.match?(path) }
    end

    #: (String path) -> bool
    def allowed?(path)
      !denied?(path) && @allow.any? { |pattern| pattern.match?(path) }
    end

    # Paths that hard-gate the PR to the human path, with the reason attached.
    #: (Array[String] paths) -> Array[Hash[Symbol, String]]
    def violations(paths)
      paths.filter_map do |path|
        if denied?(path)
          { path: path, reason: "matches a deny pattern" }
        elsif !allowed?(path)
          { path: path, reason: "matches no allow pattern (fail closed)" }
        end
      end
    end

    #: () -> Integer
    def max_files = @size_limits.fetch("max_files")

    #: () -> Integer
    def max_non_spec_lines = @size_limits.fetch("max_non_spec_lines")
  end
end

# CLI for the fix job's PRE-PUSH gate: newline-separated paths on stdin,
# exit 1 (with reasons on stderr) on any violation. `--config` is accepted
# here — unlike score.rb — because the caller stages PRISTINE copies of this
# file and the config from origin/main into RUNNER_TEMP before invoking:
# the agent can edit the working tree, so the working-tree copies of both
# must never be the judge.
if $PROGRAM_NAME == __FILE__
  require "optparse"

  config_path = SelfHealing::BlastRadius::DEFAULT_CONFIG_PATH
  OptionParser.new do |opts|
    opts.banner = "usage: blast_radius.rb [--config blast_radius.yml] < paths.txt"
    opts.on("--config PATH") { |value| config_path = value }
  end.parse!(ARGV)

  paths = $stdin.read.split("\n").map(&:strip).reject(&:empty?)
  violations = SelfHealing::BlastRadius.load(config_path).violations(paths)
  if violations.empty?
    puts "blast radius: #{paths.size} path(s) OK"
  else
    violations.each { |violation| warn "#{violation[:path]}: #{violation[:reason]}" }
    exit 1
  end
end
