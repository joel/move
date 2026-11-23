#!/usr/bin/env ruby

require "fileutils"
require_relative "../services/helpers"
require_relative "checkout_resolver"
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
        ensure_mount_sources!
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

        shell.say("Building wait helper image")
        runner.run(
          [
            "docker build #{AppCLI::ROOT}",
            "--tag #{env_config.wait_image}",
            "-f #{File.join(AppCLI::ROOT, "dockerfiles/Dockerfile-wait")}"
          ]
        )
      end

      def prepare
        setup
        if runner.image_exists?(env_config.app_image)
          ensure_ruby_version!
        else
          shell.say("App image #{env_config.app_image} missing, building it first")
          build
        end
        ensure_bundle_satisfied!
      end

      # @param prepared [Boolean] the caller already ran #prepare (restart does,
      #   before stopping the old container), so nothing can fail here first
      def start(prepared: false)
        prepare unless prepared

        return shell.say("Application already running.") if runner.container_running?(env_config.app_container)

        FileUtils.rm_f(File.join(checkout_path, "tmp/pids/server.pid"))

        runner.run(
          [
            "docker run --rm --detach",
            "--name #{env_config.app_container}",
            # Direct fallback; the browser path is https://move.move-easy.docker via move-router.
            "--publish 8080:9292",
            *network_flags,
            *app_env_flags,
            *app_volume_flags,
            "#{env_config.app_image} bin/rails s -p 9292 -b 0.0.0.0"
          ]
        )

        wait_for_app
        runner.run("docker logs #{env_config.app_container}", allow_failure: true, quiet: true)
      end

      def stop
        if runner.container_running?(env_config.app_container)
          shell.say("Stopping application container")
          runner.run("docker stop #{env_config.app_container}")
          wait_until_removed
        else
          shell.say("Application not running, skipping stop.")
        end
      end

      def teardown
        stop
        runner.remove_image(env_config.app_image)
        runner.remove_image(env_config.wait_image)
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

        prepare

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

      def ensure_running!
        return if runner.container_running?(env_config.app_container)

        raise Thor::Error, "App container is not running. Start it with `bin/cli app start`."
      end

      # Raises when neither this checkout nor the main one has config/master.key,
      # or when either file is a directory (a leftover Docker bind source). Runs
      # in setup, so restart checks it before stopping the old container.
      def ensure_mount_sources!
        sources.master_key_path
        sources.env_file_path(env_config.env)
      end

      def ensure_ruby_version!
        desired_version = env_config.ruby_version
        return if desired_version.nil?

        current_version = runner.capture(%(docker run --rm #{env_config.app_image} ruby -e "print RUBY_VERSION"),
                                         quiet: true)
        current_version = current_version.to_s.strip

        return if current_version == desired_version

        message = if current_version.empty?
                    "Unable to detect Ruby version in #{env_config.app_image}; rebuilding image."
                  else
                    "Ruby version mismatch (#{current_version} != #{desired_version}); rebuilding image."
                  end
        shell.say(message)
        build
      end

      # The dev container runs the mounted checkout on the image's gems. A
      # checkout whose Gemfile.lock is ahead of the image (a worktree, or main
      # after a pull) would crash on boot, so check before anything is stopped.
      def ensure_bundle_satisfied!
        return unless env_config.short == "dev"

        command = "docker run --rm --volume #{Shellwords.escape(checkout_path)}:/rails " \
                  "#{env_config.app_image} bundle check"
        return if runner.run(command, allow_failure: true)

        raise Thor::Error,
              "The gems in #{env_config.app_image} don't match #{checkout_path}/Gemfile.lock. " \
              "Run `bin/cli app build` (or `DOCKER_NAMESPACE=wt<n> bin/cli app build` for a private image), " \
              "then retry."
      end

      # The container runs with --rm, and Docker removes it only after
      # `docker stop` returns; a `docker run --name` before then would conflict.
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

      def wait_for_app
        unless runner.image_exists?(env_config.wait_image)
          shell.say("Wait helper image missing, skipping readiness check.")
          return
        end

        shell.say("Waiting for the web service to be ready")

        runner.run(
          [
            "docker run --rm",
            "--name #{env_config.app_container}-wait",
            "--network #{env_config.network_name}",
            "--env WAIT_HOSTS=#{env_config.app_container}:9292",
            "--env WAIT_TIMEOUT=10",
            "--env WAIT_BEFORE=1",
            "--env WAIT_SLEEP_INTERVAL=2",
            "--env WAIT_COMMAND=\"/health_check.sh\"",
            "--env WAIT_LOGGER_LEVEL=debug",
            env_config.wait_image
          ],
          allow_failure: true
        )
      end
    end
  end
end
