# frozen_string_literal: true

module SelfHealing
  # Minimal unified-diff reader: which lines were ADDED, per file. That is the
  # only diff-level evidence the scorer needs (added spec examples and
  # expectations); counts of changed lines come from the GitHub files API,
  # which is authoritative and cheaper than re-deriving them here.
  class DiffStats
    SPEC_PATH = %r{\A(?:packs/[^/]+/)?spec/}
    ADDED_EXAMPLE = /\b(?:it|specify|scenario)\b\s*(?:["']|do\b|\{)/
    ADDED_EXPECTATION = /\bexpect\s*[({]/

    #: (String diff) -> void
    def initialize(diff)
      @added_lines_by_path = parse(diff)
    end

    #: (String path) -> Array[String]
    def added_lines(path)
      @added_lines_by_path.fetch(path, [])
    end

    #: () -> Integer
    def added_spec_examples
      spec_added_lines.count { |line| line.match?(ADDED_EXAMPLE) }
    end

    #: () -> Integer
    def added_spec_expectations
      spec_added_lines.count { |line| line.match?(ADDED_EXPECTATION) }
    end

    #: (String path) -> bool
    def self.spec_path?(path)
      path.match?(SPEC_PATH)
    end

    private

    #: () -> Array[String]
    def spec_added_lines
      @added_lines_by_path.select { |path, _| self.class.spec_path?(path) }.values.flatten
    end

    #: (String diff) -> Hash[String, Array[String]]
    def parse(diff)
      result = {}
      current = nil
      diff.each_line(chomp: true) do |line|
        if (match = line.match(%r{\Adiff --git a/\S+ b/(\S+)\z}))
          current = result[match[1]] = []
        elsif current && line.start_with?("+") && !line.start_with?("+++")
          current << line.delete_prefix("+")
        end
      end
      result
    end
  end
end
