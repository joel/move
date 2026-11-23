#!/usr/bin/env ruby

require "fileutils"
require_relative "readiness_check"

module AppCLI
  module Services
    # Swaps a created replacement in for the running app container, keeping
    # the old one (stopped, renamed -prev) until the replacement answers /up,
    # and putting it back when it doesn't.
    class ContainerSwap
      PID_FILE = "tmp/pids/server.pid".freeze
      # Log lines shown when a container fails its readiness check.
      LOG_TAIL = 40

      # @param stop [#call] stops and removes the app container (AppService#stop)
      def initialize(runner:, shell:, app:, checkout_path:, readiness:, stop:)
        @runner = runner
        @shell = shell
        @app = app
        @checkout_path = checkout_path
        @readiness = readiness
        @stop = stop
      end

      # Swaps in the created container `candidate`; raises, after a rollback,
      # when it does not answer /up.
      def replace_with(candidate)
        kept = retire_running
        return promote(kept) if start_candidate(candidate)

        roll_back(kept, candidate)
      end

      # Waits for a freshly started app container (no previous one to restore).
      def await_started
        return show_logs if readiness.ready?(app)

        logs = last_logs(app)
        discard_leftover(app)
        raise Thor::Error, boot_failure(logs, "Nothing is running now. Fix the cause, then run `bin/cli app start`.")
      end

      # A container left by an interrupted restart, or an exited app container,
      # would block a create or run under its name.
      def discard_leftover(name)
        return if runner.container_status(name) == "missing"

        runner.run("docker rm --force #{name}", allow_failure: true, quiet: true)
      end

      # A -prev container means an earlier restart died between stopping the
      # old container and removing it. Refuse until the user says which wins.
      def refuse_stale_previous!
        return if runner.container_status(previous) == "missing"

        fix =
          if runner.container_running?(app)
            "If the running #{app} works, drop the old one: `docker rm --force #{previous}`. To go back to it: " \
              "`docker rm --force #{app} && docker rename #{previous} #{app} && docker start #{app}`."
          else
            "To bring it back: `docker rm --force #{app}; docker rename #{previous} #{app} && " \
              "docker start #{app}`. To drop it instead: `docker rm --force #{previous}`."
          end
        raise Thor::Error, "#{previous} is the app container an interrupted `bin/cli app restart` replaced. " \
                           "#{fix} Then run the command again."
      end

      private

      attr_reader :runner, :shell, :app, :checkout_path, :readiness

      def previous = "#{app}-prev"

      # Stops the serving container and keeps it as -prev for a rollback.
      # @return [String, nil] the kept container's name, nil when none was kept
      def retire_running
        status = runner.container_status(app)
        return if status == "missing"

        unless status == "running"
          discard_leftover(app)
          return
        end

        if auto_removed?(app)
          shell.say("#{app} was started with --rm by an older bin/cli, so it can't be kept for a rollback.")
          @stop.call
          return
        end

        # Renamed first: if the rename fails, nothing has been stopped.
        runner.run("docker rename #{app} #{previous}")
        shell.say("Stopping #{app} (kept as #{previous} until the replacement is ready)")
        runner.run("docker stop #{previous}")
        previous
      end

      # @return [Boolean] whether the replacement started and answered /up
      def start_candidate(candidate)
        runner.run("docker rename #{candidate} #{app}")
        FileUtils.rm_f(File.join(checkout_path, PID_FILE))
        runner.run("docker start #{app}")
        readiness.ready?(app)
      rescue Thor::Error => e
        shell.say("The replacement did not start: #{e.message}")
        false
      end

      def promote(kept)
        if kept && !runner.run("docker rm #{previous}", allow_failure: true, quiet: true)
          shell.say("Could not remove #{previous}; remove it with `docker rm --force #{previous}`.")
        end
        show_logs
      end

      def show_logs
        runner.run("docker logs #{app}", allow_failure: true, quiet: true)
      end

      def roll_back(kept, candidate)
        logs = last_logs(runner.container_status(app) == "missing" ? candidate : app)
        [app, candidate].each { |name| discard_leftover(name) }
        raise Thor::Error, boot_failure(logs, restore_previous(kept))
      end

      # @return [String] what state the rollback left, for the error message
      def restore_previous(kept)
        unless kept
          return "No previous container was kept, so nothing is running now. Fix the cause, then run " \
                 "`bin/cli app start`."
        end

        source = mount_source(previous)
        FileUtils.rm_f(File.join(source, PID_FILE)) if source
        runner.run("docker rename #{previous} #{app}")
        runner.run("docker start #{app}")
        return "The previous #{app} is back and serving." if readiness.ready?(app)

        "The previous #{app} was started again but did not answer /up either; see `bin/cli app logs`."
      rescue Thor::Error => e
        "Restoring the previous container failed (#{e.message}). Restore it by hand: " \
        "`docker rename #{previous} #{app} && docker start #{app}`."
      end

      def boot_failure(logs, outcome)
        "#{app} (#{checkout_path}) did not answer /up (it exited, or #{ReadinessCheck::TIMEOUT_ENV} ran out). " \
          "Its last log lines:\n#{logs.strip}\n\n#{outcome}"
      end

      def last_logs(name)
        runner.capture("docker logs --tail #{LOG_TAIL} #{name}", quiet: true).to_s
      end

      def auto_removed?(name)
        runner.capture("docker inspect --format '{{.HostConfig.AutoRemove}}' #{name}", quiet: true).to_s.strip == "true"
      end

      # The host checkout mounted at /rails, where the container's server.pid lives.
      def mount_source(name)
        format = %q('{{range .Mounts}}{{if eq .Destination "/rails"}}{{.Source}}{{end}}{{end}}')
        source = runner.capture("docker inspect --format #{format} #{name}", quiet: true).to_s.strip
        source.empty? ? nil : source
      end
    end
  end
end
