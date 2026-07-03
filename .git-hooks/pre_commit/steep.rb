# frozen_string_literal: true

module Overcommit
  module Hook
    module PreCommit
      # Type-check the actions layer with Steep before the commit lands.
      #
      # Steep reads the inline `#:`/`@rbs` annotations (Steepfile `inline: true`)
      # plus the hand shims under sig/. The same check runs merge-blocking in
      # CI's `lint` job; this hook is the local fast-fail (~2s — Steep only
      # checks app/actions, no DB, no Rails boot). Only runs when files under
      # app/actions/, sig/, or the Steepfile are staged (see `include` in
      # .overcommit.yml). Always whole-target: signatures are cross-file, so a
      # staged shim edit can break an unstaged action and vice versa.
      # --no-daemon: the steep server daemon can deadlock in headless
      # environments. See doc/project/type-checking.md.
      class Steep < Base
        def run
          result = execute(%w[bundle exec steep check --no-daemon --severity-level=error])
          return :pass if result.success?

          [:fail, (result.stdout.to_s + result.stderr.to_s).strip]
        end
      end
    end
  end
end
