# frozen_string_literal: true

module Overcommit
  module Hook
    module CommitMsg
      # Reject CI/deploy skip markers in commit messages.
      #
      # GitHub treats [skip ci] (and variants) anywhere in a commit message as a
      # platform-level skip that suppresses ALL workflow runs for the push. When
      # such a marker rides along in a squash-merge commit (aggregated from the
      # branch's commit messages), it silently skips the production deploy and CI
      # for the merge. Docs are excluded from CI via paths-ignore in
      # .github/workflows/ci.yml — never via [skip ci].
      class ForbidSkipMarkers < Base
        # GitHub honors two skip syntaxes in a commit message, both of which
        # suppress push/PR workflows: the bracketed markers (anywhere) and the
        # `skip-checks: true` trailer (in the commit description). See GitHub's
        # "Skipping workflow runs" docs. Reject both.
        MARKERS = /\[(?:skip[ -]ci|ci[ -]skip|no[ -]ci|skip[ -]actions|actions[ -]skip|skip[ -]deploy)\]/i
        TRAILER = /skip-checks:\s*true/i
        PATTERN = Regexp.union(MARKERS, TRAILER)

        def run
          offending = commit_message_lines.grep(PATTERN)
          return :pass if offending.empty?

          [:fail, <<~MSG.strip]
            Remove CI/deploy skip markers from the commit message — they leak into
            squash merges and suppress the production deploy/CI for the whole push.
            Docs are excluded from CI via paths-ignore in ci.yml, not [skip ci].
            Offending line(s): #{offending.map(&:strip).join(" / ")}
          MSG
        end
      end
    end
  end
end
