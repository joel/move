#!/usr/bin/env ruby

require "open3"
require "thor"
require_relative "../services/helpers"

module AppCLI
  module Services
    # A git checkout bin/cli can mount at /rails: the main checkout or one of its
    # worktrees.
    Checkout = Struct.new(:path, :branch, :main, keyword_init: true) do
      def main?
        main ? true : false
      end

      def describe
        "#{path} (branch #{branch})"
      end
    end

    # Resolves the `--repo <target>` option of `bin/cli app run|test` to a Checkout.
    #
    # - no value                     → the main checkout (first `git worktree list` entry)
    # - starts with `/`, `.` or `~`  → a path to a checkout
    # - anything else                → a worktree name: branch first, then directory name
    #
    # It never falls back to the current directory: an unknown name is an error.
    class CheckoutResolver
      PATH_PREFIXES = ["/", ".", "~"].freeze

      # @param root [String] the checkout bin/cli itself lives in
      # @param git [#call] `git.call(*args)` → [stdout, success]; injectable for specs
      def initialize(root: AppCLI::ROOT, git: nil)
        @root = root
        @git = git || method(:system_git)
      end

      def resolve(target = nil)
        value = target.to_s.strip
        return main_checkout if value.empty?
        return resolve_path(value) if value.start_with?(*PATH_PREFIXES)

        resolve_name(value)
      end

      def main_checkout
        entry = worktrees.first
        return Checkout.new(path: root, branch: branch_at(root), main: true) unless entry

        to_checkout(entry)
      end

      # The checkout at `path` as it stands, without resolving it against the
      # worktree list (for naming a lock holder).
      def checkout_at(path)
        Checkout.new(path: path, branch: branch_at(path), main: false)
      end

      def worktrees
        @worktrees ||= begin
          output, ok = git.call("-C", root, "worktree", "list", "--porcelain")
          ok ? parse_porcelain(output) : []
        end
      end

      private

      attr_reader :root, :git

      def resolve_path(value)
        path = File.expand_path(value)
        unless File.directory?(path) && File.file?(File.join(path, "Gemfile"))
          raise Thor::Error, "--repo #{value}: #{path} is not a checkout (no Gemfile there)."
        end

        real = File.realpath(path)
        entry = worktrees.find { |wt| same_path?(wt[:path], real) }
        return to_checkout(entry) if entry

        Checkout.new(path: real, branch: branch_at(real), main: false)
      end

      def resolve_name(value)
        matches = matching_worktrees(value)
        raise Thor::Error, unknown_message(value) if matches.empty?
        raise Thor::Error, ambiguous_message(value, matches) if matches.size > 1

        entry = matches.first
        raise Thor::Error, missing_message(value, entry) if entry[:prunable] || !File.directory?(entry[:path])

        to_checkout(entry)
      end

      # Branch names win over directory names.
      def matching_worktrees(value)
        by_branch = worktrees.select { |wt| wt[:branch] == value }
        return by_branch unless by_branch.empty?

        worktrees.select { |wt| File.basename(wt[:path]) == value }
      end

      def to_checkout(entry)
        Checkout.new(path: entry[:path], branch: entry[:branch] || "detached", main: entry[:main])
      end

      def parse_porcelain(output)
        output.split(/\n{2,}/).filter_map { |block| parse_block(block) }.each_with_index.map do |wt, index|
          wt.merge(main: index.zero?)
        end
      end

      def parse_block(block)
        entry = {}
        block.each_line(chomp: true) do |line|
          key, rest = line.split(" ", 2)
          case key
          when "worktree" then entry[:path] = rest
          when "branch" then entry[:branch] = rest.delete_prefix("refs/heads/")
          when "prunable" then entry[:prunable] = true
          end
        end
        entry[:path] ? entry : nil
      end

      def branch_at(path)
        output, ok = git.call("-C", path, "rev-parse", "--abbrev-ref", "HEAD")
        name = output.to_s.strip
        return "unknown" if !ok || name.empty?

        name == "HEAD" ? "detached" : name
      end

      def same_path?(left, right)
        File.exist?(left) && File.realpath(left) == right
      end

      def listing
        worktrees.map { |wt| "  #{wt[:path]} [#{wt[:branch] || "detached"}]" }.join("\n")
      end

      def unknown_message(value)
        "--repo #{value}: no worktree has that branch or directory name. Known worktrees:\n#{listing}"
      end

      def ambiguous_message(value, matches)
        paths = matches.map { |wt| "  #{wt[:path]}" }.join("\n")
        "--repo #{value} is ambiguous; it matches:\n#{paths}\nPass the path instead."
      end

      def missing_message(value, entry)
        "--repo #{value}: worktree #{entry[:path]} is registered but missing on disk. " \
          "Run `git worktree prune` to drop it."
      end

      def system_git(*)
        output, status = Open3.capture2("git", *, err: File::NULL)
        [output, status.success?]
      rescue Errno::ENOENT
        ["", false]
      end
    end
  end
end
