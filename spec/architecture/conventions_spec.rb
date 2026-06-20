# frozen_string_literal: true

require "rails_helper"

# Architecture fitness tests — encode the AGENTS.md §1 layering conventions as
# executable, CI-enforced assertions so structural drift fails loudly instead of
# being caught (or missed) in review. Each failure names the offending file(s).
# Complements the line-level `Move/*` RuboCop cops with layer/structure checks.
# See .github/codex/review-rubric.md.
RSpec.describe "Architecture conventions" do
  # Code lines (comments stripped) in `glob` matching `pattern`, as "path:line",
  # skipping any file whose path contains an `except:` fragment.
  def grep_app(glob, pattern, except: [])
    relative_paths(glob, except).flat_map { |rel| matches_in(rel, pattern) }
  end

  def relative_paths(glob, except)
    Rails.root.glob(glob)
         .map { |path| path.relative_path_from(Rails.root).to_s }
         .reject { |rel| except.any? { |fragment| rel.include?(fragment) } }
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
      expect(grep_app("app/models/**/*.rb", /[A-Z]\w*::[A-Z]\w*\.new\.call/)).to be_empty
    end

    it "do not use Dry::Monads (the action layer's railway)" do
      expect(grep_app("app/models/**/*.rb", /Dry::Monads/)).to be_empty
    end

    it "do not emit domain events (actions emit them)" do
      expect(grep_app("app/models/**/*.rb", /Rails\.event\.notify/)).to be_empty
    end
  end

  describe "controllers stay thin (authorize → call action → render)" do
    it "do not open database transactions (multi-step persistence belongs in actions)" do
      expect(grep_app("app/controllers/**/*.rb", /\.transaction\b/)).to be_empty
    end
  end

  describe "domain events are emitted from the action layer" do
    it "Rails.event.notify lives only in app/actions (+ MCP audit infrastructure)" do
      hits = grep_app("app/**/*.rb", /Rails\.event\.notify/,
                      except: ["app/actions/", "app/mcp/move_mcp/audit.rb"])

      expect(hits).to be_empty, "Rails.event.notify outside the action layer: #{hits.join(", ")}"
    end
  end
end
