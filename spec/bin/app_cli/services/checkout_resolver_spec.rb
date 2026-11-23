require "spec_helper"
require "tmpdir"
require_relative "../../../../bin/cli-files/app-cmd/checkout_resolver"

RSpec.describe AppCLI::Services::CheckoutResolver do
  subject(:resolver) { described_class.new(root: feature, git: git) }

  let(:tmp) { File.realpath(Dir.mktmpdir("resolver")) }
  let(:entries) { [[main, "main"], [feature, "fix/862-cli"]] }
  let(:calls) { [] }
  let(:git) do
    lambda do |*args|
      calls << args
      args.include?("worktree") ? [porcelain(*entries), true] : ["some-branch\n", true]
    end
  end

  after { FileUtils.remove_entry(tmp) }

  def main = checkout_dir("move")
  def feature = checkout_dir("wt-feature")

  def checkout_dir(name)
    path = File.join(tmp, name)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, "Gemfile"), "")
    path
  end

  def porcelain(*entries)
    blocks = entries.map do |path, branch, extra|
      lines = ["worktree #{path}", "HEAD abc123"]
      lines << (branch ? "branch refs/heads/#{branch}" : "detached")
      lines << extra if extra
      lines.join("\n")
    end
    "#{blocks.join("\n\n")}\n"
  end

  it "defaults to the main checkout, even when bin/cli runs from a worktree" do
    checkout = resolver.resolve(nil)
    expect([checkout.path, checkout.branch, checkout.main?]).to eq([main, "main", true])
    expect(calls.first).to eq(["-C", feature, "worktree", "list", "--porcelain"])
  end

  it "falls back to its own root when git cannot list worktrees" do
    failing = ->(*) { ["", false] }
    checkout = described_class.new(root: main, git: failing).resolve("")
    expect([checkout.path, checkout.branch]).to eq([main, "unknown"])
  end

  it "matches a branch name with slashes" do
    expect(resolver.resolve("fix/862-cli").path).to eq(feature)
  end

  it "matches a directory name" do
    checkout = resolver.resolve("wt-feature")
    expect([checkout.path, checkout.branch, checkout.main?]).to eq([feature, "fix/862-cli", false])
  end

  it "prefers a branch match over a directory match" do
    other = checkout_dir("other")
    entries.replace([[main, "main"], [feature, "fix/862-cli"], [other, "wt-feature"]])
    expect(resolver.resolve("wt-feature").path).to eq(other)
  end

  it "lists the known worktrees for an unknown name" do
    expect { resolver.resolve("nope") }.to raise_error(Thor::Error) { |error|
      expect(error.message).to include("--repo nope", "#{main} [main]", "#{feature} [fix/862-cli]")
    }
  end

  it "names the matching paths when a name is ambiguous" do
    a = checkout_dir("a/dup")
    b = checkout_dir("b/dup")
    entries.replace([[main, "main"], [a, nil], [b, nil]])
    expect { resolver.resolve("dup") }.to raise_error(Thor::Error, /ambiguous.*#{a}.*#{b}/m)
  end

  it "suggests git worktree prune for a registered worktree that is missing on disk" do
    gone = File.join(tmp, "gone")
    entries.replace([[main, "main"], [gone, "old", "prunable gitdir file points to non-existent location"]])
    expect { resolver.resolve("old") }.to raise_error(Thor::Error, /missing on disk.*git worktree prune/)
  end

  it "detects a missing worktree directory even without a prunable mark" do
    entries.replace([[main, "main"], [File.join(tmp, "gone"), "old"]])
    expect { resolver.resolve("old") }.to raise_error(Thor::Error, /git worktree prune/)
  end

  it "treats values starting with /, . or ~ as paths" do
    expect(resolver.resolve(feature).path).to eq(feature)
    Dir.chdir(tmp) { expect(resolver.resolve("./wt-feature").branch).to eq("fix/862-cli") }
    home = Dir.home
    ENV["HOME"] = tmp
    expect(resolver.resolve("~/wt-feature").path).to eq(feature)
  ensure
    ENV["HOME"] = home
  end

  it "reads the branch of an unregistered checkout path from git" do
    loose = checkout_dir("loose")
    checkout = resolver.resolve(loose)
    expect([checkout.path, checkout.branch, checkout.main?]).to eq([loose, "some-branch", false])
  end

  it "refuses a path that is not a checkout" do
    expect { resolver.resolve("/nonexistent/x") }.to raise_error(Thor::Error, /not a checkout/)
  end

  it "never treats a bare name as a path relative to the current directory" do
    Dir.chdir(tmp) do
      checkout_dir("loose")
      expect { resolver.resolve("loose") }.to raise_error(Thor::Error, /no worktree/)
    end
  end
end
