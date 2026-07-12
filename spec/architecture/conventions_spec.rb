# frozen_string_literal: true

require "rails_helper"

# Architecture fitness tests — encode the AGENTS.md §1 layering conventions as
# executable, CI-enforced assertions so structural drift fails loudly instead of
# being caught (or missed) in review. Each failure names the offending file(s).
# Complements the line-level `Move/*` RuboCop cops with layer/structure checks.
# See .github/codex/review-rubric.md.
RSpec.describe "Architecture conventions" do
  # The layer conventions apply to code wherever it lives — both the flat root
  # tree (app/…) and the extracted Packwerk domain packs (packs/*/app/…). These
  # globs keep the fitness tests governing a domain after it is carved into a pack.
  # Model files in a pack live in app/models (private) or app/public (the public
  # data contract); public *actions* stay in app/actions and are exposed with the
  # `# pack_public: true` sigil, so the action-layer globs/excludes below catch them
  # via the shared `app/actions/` path fragment. See doc/project/packwerk-boundaries.md.
  #
  # `model_globs` deliberately scans a pack's app/public/ as part of the model layer:
  # app/public is reserved for persistence/data contracts (ApplicationRecord
  # subclasses + pure-data structs), which — like models — must not use Dry::Monads
  # or emit events. A file there that does is a misplaced action, and failing these
  # checks is the intended signal (move it to app/actions + the sigil).
  def model_globs
    ["app/models/**/*.rb", "packs/*/app/models/**/*.rb", "packs/*/app/public/**/*.rb"]
  end

  def all_code_glob
    "{app,packs/*/app}/**/*.rb"
  end

  # Code lines (comments stripped) in `glob`(s) matching `pattern`, as "path:line",
  # skipping any file whose path contains an `except:` fragment. `glob` may be a
  # single pattern or an array of patterns.
  def grep_app(glob, pattern, except: [])
    Array(glob).flat_map { |g| relative_paths(g, except) }
               .flat_map { |rel| matches_in(rel, pattern) }
  end

  def relative_paths(glob, except)
    # rel is a String path and `include?` is SUBSTRING matching — the cop's
    # suggested Array#intersect? would raise TypeError.
    Rails.root.glob(glob)
         .map { |path| path.relative_path_from(Rails.root).to_s }
         .reject { |rel| except.any? { |fragment| rel.include?(fragment) } } # rubocop:disable Style/ArrayIntersect
  end

  def matches_in(rel, pattern)
    File.foreach(Rails.root.join(rel)).with_index.filter_map do |line, i|
      code = line.sub(/#.*$/, "") # ignore trailing comments
      "#{rel}:#{i + 1}" if !code.strip.empty? && code.match?(pattern)
    end
  end

  describe "actions are the railway-typed business-logic layer" do
    it "every BaseAction subclass implements its own #call" do
      Rails.application.eager_load! # populate BaseAction.descendants (idempotent)
      missing = BaseAction.descendants.reject { |klass| klass.method_defined?(:call, false) }

      expect(missing).to be_empty,
                         "actions missing their own #call: #{missing.map(&:name).join(", ")}"
    end
  end

  describe "models stay persistence-focused (associations / validations / scopes)" do
    it "do not invoke domain actions (business logic belongs in app/actions)" do
      expect(grep_app(model_globs, /[A-Z]\w*::[A-Z]\w*\.new\.call/)).to be_empty
    end

    it "do not use Dry::Monads (the action layer's railway)" do
      expect(grep_app(model_globs, /Dry::Monads/)).to be_empty
    end

    it "do not emit domain events (actions emit them)" do
      expect(grep_app(model_globs, /Rails\.event\.notify/)).to be_empty
    end
  end

  describe "controllers stay thin (authorize → call action → render)" do
    it "do not open database transactions (multi-step persistence belongs in actions)" do
      expect(grep_app(["app/controllers/**/*.rb", "packs/*/app/controllers/**/*.rb"],
                      /\.transaction\b/)).to be_empty
    end
  end

  describe "domain events are emitted from the action layer" do
    it "Rails.event.notify lives only in app/actions (+ MCP audit infrastructure)" do
      # The `app/actions/` fragment also matches a pack's packs/*/app/actions/ path,
      # so publicized entry-point actions inside a pack are correctly excluded.
      hits = grep_app(all_code_glob, /Rails\.event\.notify/,
                      except: ["app/actions/", "app/mcp/move_mcp/audit.rb"])

      expect(hits).to be_empty, "Rails.event.notify outside the action layer: #{hits.join(", ")}"
    end
  end

  describe "the Ui component kit is browsable in Lookbook (AGENTS.md §7)" do
    it "every renderable Ui component has a Lookbook preview" do
      Rails.application.eager_load! # populate Components::Ui constants (idempotent)
      renderable = Components::Ui.constants
                                 .map { |name| Components::Ui.const_get(name) }
                                 .select { |const| const.is_a?(Class) && const < Components::Base }
      missing = renderable.reject do |klass|
        Rails.root.join("spec/components/previews/ui",
                        "#{klass.name.demodulize.underscore}_preview.rb").exist?
      end

      # Non-renderable helpers (e.g. the NavDestinations data module) are exempt
      # by construction — only Phlex renderables need a browsable preview.
      expect(missing).to be_empty,
                         "Ui components without a Lookbook preview " \
                         "(spec/components/previews/ui/<name>_preview.rb — AGENTS.md §7): " \
                         "#{missing.map(&:name).join(", ")}"
    end
  end

  describe "soft-deleted data is retention-bounded (#582)" do
    it "the purge sweep covers every Discardable model" do
      Rails.application.eager_load! # populate ApplicationRecord.descendants (idempotent)
      discardable = ApplicationRecord.descendants.select { |klass| klass.include?(Discardable) }
      missing = discardable - Discards::PurgeExpired::PASSES

      # A model gaining `include Discardable` without joining PASSES would retain
      # its discarded rows (and blobs) forever — the exact drift this test forbids.
      expect(missing).to be_empty,
                         "Discardable models missing from Discards::PurgeExpired::PASSES: " \
                         "#{missing.map(&:name).join(", ")}"
      expect(Discards::PurgeExpired::PASSES).to match_array(discardable)
    end
  end
end
