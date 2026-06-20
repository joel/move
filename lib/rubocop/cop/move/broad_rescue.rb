# frozen_string_literal: true

module RuboCop
  module Cop
    module Move
      # Flags broad rescues — a bare `rescue` or `rescue StandardError` — which
      # swallow *every* StandardError, including unexpected ones (NoMethodError,
      # ArgumentError, dropped connections, future bugs in the body). That hides
      # real failures and defeats fail-fast. Rescue the specific error class(es)
      # you actually expect.
      #
      # A best-effort broad rescue at a *trust boundary* is legitimate and
      # documented (AGENTS.md §1 #4 — a Rails.event subscriber / Turbo broadcast
      # must never break its emitter; an advisory AI call degrades gracefully). The
      # cop intentionally does not exempt these by location, because "boundary vs
      # core domain logic" can't be inferred from the AST — it forces the call to
      # be explicit. Opt out per-site so the exception is conscious and reviewable:
      # add an inline disable directive naming this cop, with a one-line reason
      # (e.g. "subscriber: a broadcast failure must not break the emitting action").
      #
      # @example
      #   # bad
      #   begin
      #     do_work
      #   rescue StandardError
      #     nil
      #   end
      #
      #   # bad (bare rescue == rescue StandardError)
      #   def f = work rescue fallback
      #
      #   # good
      #   begin
      #     do_work
      #   rescue ActiveRecord::StatementInvalid => e
      #     handle(e)
      #   end
      class BroadRescue < Base
        MSG = "Avoid a broad `rescue` (bare `rescue` / `rescue StandardError`): it " \
              "swallows unexpected errors and hides bugs. Rescue the specific error " \
              "class(es) you expect. If a trust-boundary best-effort rescue is " \
              "intentional (subscriber / broadcast / advisory — AGENTS.md §1 #4), opt " \
              "out per-site with `# rubocop:disable Move/BroadRescue` and a reason."

        def on_resbody(node)
          add_offense(node.loc.keyword) if broad?(node.children.first)
        end

        private

        # A bare `rescue` (nil exception list, implicitly StandardError) or a list
        # that names StandardError.
        def broad?(exceptions)
          return true if exceptions.nil?

          exceptions.array_type? && exceptions.children.any? { |c| standard_error?(c) }
        end

        def standard_error?(node)
          node.const_type? && node.short_name == :StandardError
        end
      end
    end
  end
end
