#!/usr/bin/env ruby

require "fileutils"
require_relative "../services/helpers"
require_relative "app_preflight"
require_relative "checkout_resolver"
require_relative "container_swap"
require_relative "container_flags"
require_relative "mount_sources"

module AppCLI
  module Services
    class AppService
      # How long #stop waits for Docker to remove the --rm container.
      REMOVAL_POLLS = 20
      REMOVAL_POLL_INTERVAL = 0.5

      # @param checkout_path [String] the checkout mounted at /rails (the one bin/cli lives in)
      # @param main_path [String, nil] fallback for gitignored files; default: the main checkout
      def initialize(shell:, env:, runner: nil, checkout_path: AppCLI::ROOT, main_path: nil)
        @runner = runner || CommandRunner.new(shell: shell)
        @shell = shell
        @env_config = EnvConfig.new(env)
        @checkout_path = checkout_path
        @main_path = main_path
      end

      def setup
        runner.ensure_network(env_config.network_name)
        checks.mount_sources!
        runner.ensure_mysql_certs if env_config.mysql?
        ensure_sqlite_db_dir
      end

      def build
        shell.say("Building #{env_config.app_name} app image")
        build_args = [
          "docker build #{AppCLI::ROOT}",
          "--tag #{env_config.app_image}",
          "-f #{env_config.dockerfile_path}"
        ]
        if (ruby_version = env_config.ruby_version)
          build_args << "--build-arg RUBY_VERSION=#{ruby_version}"
        end
        runner.run(build_args)
      end

      # Resolves and validates every input of the app container (network +
      # AppPreflight). It raises before anything is stopped or removed.
      def preflight
        setup
        checks.image_and_volumes!
      end

      def start
        preflight
        swap.refuse_stale_previous!

        return shell.say("Application already running.") if runner.container_running?(app)

        swap.discard_leftover(app)
        FileUtils.rm_f(File.join(checkout_path, ContainerSwap::PID_FILE))
        runner.run(["docker run --detach", *server_args(app)])
        swap.await_started
      end

      # Replaces the running app container, or starts one. The caller runs
      # #preflight first. The replacement is created (not started) under a
      # temporary name while the old one still serves, so Docker has accepted
      # its flags, env file, image and network before anything is stopped.
      #
      # The old container is then stopped and kept as -prev (not removed)
      # until the replacement answers /up. If it doesn't, the replacement is
      # removed, -prev is renamed back and started, and this raises with the
      # replacement's last log lines.
      def replace
        swap.refuse_stale_previous!
        candidate = "#{app}-next"
        swap.discard_leftover(candidate)
        runner.run(["docker create", *server_args(candidate)])

        swap.replace_with(candidate)
      end

      def stop
        status = runner.container_status(app)
        return shell.say("Application not running, skipping stop.") if status == "missing"

        if status == "running"
          shell.say("Stopping application container")
          runner.run("docker stop #{app}")
        end
        # Containers started before #879 run with --rm and go on their own.
        runner.run("docker rm #{app}", allow_failure: true, quiet: true) unless container_removed?
        wait_until_removed
      end

      def teardown
        stop
        runner.remove_image(env_config.app_image)
      end

      def logs(follow: true)
        args = follow ? "-f" : ""
        runner.run("docker logs #{args} #{env_config.app_container}")
      end

      def status
        runner.container_status(env_config.app_container)
      end

      def connect
        ensure_running!
        runner.run("docker exec -it #{env_config.app_container} bash")
      end

      def console
        ensure_running!
        runner.run("docker exec -it #{env_config.app_container} bin/rails console")
      end

      def migrate
        exec(%w[bin/rails db:migrate])
      end

      def schema_dump
        unless runner.container_running?(env_config.app_container)
          shell.say("App container not running. Start it to dump schema.")
          return
        end

        exec(%w[bin/rails db:schema:dump])
        copy_schema_from_container(env_config.app_container)
      end

      def exec(command_parts, reuse_existing: true)
        raise Thor::Error, "No command provided for app exec." if command_parts.empty?

        escaped = command_parts.map { |p| Shellwords.escape(p) }.join(" ")

        if reuse_existing && runner.container_running?(env_config.app_container)
          runner.run(%(docker exec -it #{env_config.app_container} bash -c #{Shellwords.escape(escaped)}))
          return
        end

        preflight

        runner.run(
          [
            "docker run --rm",
            *network_flags,
            *app_env_flags,
            *app_volume_flags,
            "#{env_config.app_image} sh -c #{Shellwords.escape(escaped)}"
          ]
        )
      end

      private

      attr_reader :runner, :shell, :env_config, :checkout_path

      def app = env_config.app_container

      # Built (and MOVE_APP_READY_TIMEOUT read) before anything is stopped, so
      # a bad timeout fails early.
      def swap
        @swap ||= ContainerSwap.new(
          runner: runner, shell: shell, app: app, checkout_path: checkout_path, stop: method(:stop),
          readiness: ReadinessCheck.new(runner: runner, shell: shell, timeout: ReadinessCheck.timeout)
        )
      end

      def server_args(name)
        [
          "--name #{name}",
          # Direct fallback; the browser path is https://move.move-easy.docker via move-router.
          "--publish 8080:9292",
          *network_flags,
          *app_env_flags,
          *app_volume_flags,
          "#{env_config.app_image} bin/rails s -p 9292 -b 0.0.0.0"
        ]
      end

      def ensure_running!
        return if runner.container_running?(env_config.app_container)

        raise Thor::Error, "App container is not running. Start it with `bin/cli app start`."
      end

      # A --rm container is removed by Docker only after `docker stop` returns;
      # a `docker run --name` before then would conflict.
      def wait_until_removed
        REMOVAL_POLLS.times do
          return if container_removed?

          sleep(REMOVAL_POLL_INTERVAL)
        end
        runner.run("docker rm --force #{env_config.app_container}", allow_failure: true)
        return if container_removed?

        raise Thor::Error, "#{env_config.app_container} is still there after `docker stop`. " \
                           "Remove it with `docker rm -f #{env_config.app_container}`, then run `bin/cli app start`."
      end

      def container_removed?
        runner.container_status(env_config.app_container) == "missing"
      end

      def ensure_sqlite_db_dir
        return unless env_config.sqlite3?

        FileUtils.mkdir_p(File.join(AppCLI::ROOT, "db"))
      end

      # config/master.key and .env.<env> are gitignored, so a worktree reads
      # them from the main checkout when it has none (never copied).
      def checks
        @checks ||= AppPreflight.new(env_config: env_config, runner: runner, shell: shell, sources: sources,
                                     checkout_path: checkout_path, build: method(:build))
      end

      def sources
        @sources ||= MountSources.new(checkout_path: checkout_path, main_path: main_path)
      end

      def main_path
        @main_path ||= CheckoutResolver.new(root: checkout_path).main_checkout.path
      end

      def container_flags
        @container_flags ||= ContainerFlags.new(env_config: env_config, checkout_path: checkout_path, sources: sources)
      end

      def app_env_flags
        container_flags.env
      end

      def app_volume_flags
        container_flags.volumes
      end

      def network_flags
        container_flags.network
      end

      def copy_schema_from_container(container_name)
        # schema_format is :sql, so db:schema:dump writes db/structure.sql.
        runner.run("docker cp #{container_name}:/rails/db/structure.sql db/structure.sql")
      end
    end
  end
end
