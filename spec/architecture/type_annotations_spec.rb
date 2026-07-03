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
  # Every pack's actions are checked (#519) and so are the models (#521), so
  # the globs are general — NEW packs/models are held to the annotation
  # convention from day one. The concerns/ exclusion mirrors the Steepfile's
  # (their `included do` DSL bodies are unmodellable — see there).
  def steep_checked_globs
    [
      "app/actions/**/*.rb", "packs/*/app/actions/**/*.rb",
      "app/models/**/*.rb", "packs/*/app/public/**/*.rb",
      "packs/*/app/models/**/*.rb"
    ]
  end

  def excluded_from_checking
    ["packs/utility/app/models/concerns/"]
  end

  # A def is annotated when the nearest preceding non-blank line is an inline
  # RBS annotation: a `#:` method type, the last line of a multi-`#:` overload
  # stack, an `@rbs` doc-style/method-type comment, or (for `def self.`, which
  # inline RBS cannot declare yet) the `# @rbs skip` escape hatch — whose
  # signature must then live in a sig/*.rbs file.
  def annotation_line
    /\A\s*#(?::|\s*@rbs\b)/
  end

  def checked_files
    steep_checked_globs.flat_map { |glob| Rails.root.glob(glob) }
                       .map { |path| path.relative_path_from(Rails.root).to_s }
                       .reject { |rel| excluded_from_checking.any? { |fragment| rel.include?(fragment) } }
  end

  def unannotated_defs
    checked_files.flat_map do |rel|
      lines = Rails.root.join(rel).readlines
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

  # The glob above only proves annotations EXIST; this proves Steep actually
  # CHECKS them — a new pack/model dir whose `check` line is missing from the
  # Steepfile would otherwise carry annotations that are never type-checked,
  # green in CI. A directory may alternatively be covered file-by-file (the
  # packs/utility/app/models case — its concerns/ must stay unchecked), in
  # which case every non-excluded .rb file needs its own check line.
  it "every checked-scope directory has its check line(s) in the Steepfile" do
    steepfile = Rails.root.join("Steepfile").read
    dirs = Rails.root.glob("packs/*/app/{actions,public,models}") + [Rails.root.join("app/models")]

    missing = dirs.filter_map do |dir|
      rel = dir.relative_path_from(Rails.root).to_s
      next if steepfile.include?(%(check "#{rel}"))

      files = Rails.root.glob("#{rel}/**/*.rb")
                   .map { |f| f.relative_path_from(Rails.root).to_s }
                   .reject { |f| excluded_from_checking.any? { |fragment| f.include?(fragment) } }
      rel unless files.any? && files.all? { |f| steepfile.include?(%(check "#{f}")) }
    end

    expect(missing).to be_empty, <<~MSG
      Checked-scope directories missing from the Steepfile's :actions target
      (their inline annotations would never be type-checked):
      #{missing.join("\n")}
    MSG
  end
end
