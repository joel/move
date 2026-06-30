# frozen_string_literal: true

module Overcommit
  module Hook
    module PreCommit
      # Enforce Packwerk domain boundaries locally, before the commit lands.
      #
      # Packwerk maps every constant to its owning package and flags references
      # that break a pack's declared dependencies, privacy (non-app/public
      # constants), visibility, or architecture layer. The same `packwerk check`
      # runs merge-blocking in CI; this hook is the local fast-fail so a boundary
      # violation is caught at commit time rather than on the PR. Only runs when
      # Ruby files under app/ or packs/ are staged (see `include` in .overcommit.yml),
      # so docs/config commits skip the (Rails-booting) check.
      # See doc/project/packwerk-boundaries.md.
      class Packwerk < Base
        def run
          ruby_files = applicable_files.select { |file| File.extname(file) == ".rb" }
          return :pass if ruby_files.empty?

          result = execute(%w[bundle exec packwerk check] + ruby_files)
          return :pass if result.success?

          [:fail, (result.stdout.to_s + result.stderr.to_s).strip]
        end
      end
    end
  end
end
