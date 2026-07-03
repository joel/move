# frozen_string_literal: true

require "rails_helper"

# Type-annotation coverage fitness test — the ratchet Steep itself cannot be.
#
# Steep verifies that annotated methods honour their declared contracts, but an
# UNANNOTATED method silently types as `(?) -> untyped` and passes — so without
# this spec, coverage regresses invisibly one new method at a time. AGENTS.md §1
# rule 7 makes annotations mandatory in the checked scope; this encodes that as
# an executable assertion, in the spirit of conventions_spec.rb.
# See doc/project/type-checking.md.
RSpec.describe "Type annotation coverage" do
  # Must mirror the `check` path(s) of the :actions target in the Steepfile.
  def steep_checked_globs
    ["app/actions/**/*.rb"]
  end

  # A def is annotated when the nearest preceding non-blank line is an inline
  # RBS annotation: a `#:` method type, the last line of a multi-`#:` overload
  # stack, an `@rbs` doc-style/method-type comment, or (for `def self.`, which
  # inline RBS cannot declare yet) the `# @rbs skip` escape hatch — whose
  # signature must then live in a sig/*.rbs file.
  def annotation_line
    /\A\s*#(?::|\s*@rbs\b)/
  end

  def unannotated_defs
    steep_checked_globs.flat_map { |glob| Rails.root.glob(glob) }.flat_map do |path|
      rel = path.relative_path_from(Rails.root).to_s
      lines = File.readlines(path)
      lines.each_with_index.filter_map do |line, i|
        next unless line.match?(/\A\s*def\s/)

        preceding = lines[0...i].rfind { |l| !l.strip.empty? }
        "#{rel}:#{i + 1}" unless preceding&.match?(annotation_line)
      end
    end
  end

  it "every def in the Steep-checked scope carries an inline RBS annotation" do
    offenders = unannotated_defs

    expect(offenders).to be_empty, <<~MSG
      Methods without a `#:` / `@rbs` inline annotation directly above the def
      (see doc/project/type-checking.md for the convention):
      #{offenders.join("\n")}
    MSG
  end
end
