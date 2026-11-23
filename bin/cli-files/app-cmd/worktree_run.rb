#!/usr/bin/env ruby

require "digest"
require "shellwords"
require_relative "../services/helpers"
require_relative "../db-cmd/db_service"
require_relative "container_flags"
require_relative "mount_sources"
require_relative "test_lock"

module AppCLI
  module Services
    # Throwaway app containers for one checkout: `bin/cli app run` and
    # `bin/cli app test`. They mount the checkout at /rails, join the Docker
    # network and leave the long-lived dev container alone.
    class WorktreeRun
      TEST_CONTAINER = "#{APP_NAME}-app-test".freeze
      LOCK_FILE = "tmp/bin-cli-app-test.lock".freeze
      DEFAULT_TEST_ARGS = ["spec", "--exclude-pattern", "spec/system/**/*_spec.rb"].freeze

      # @param checkout [Checkout] the checkout to mount
      # @param main_path [String] the main checkout (fallback for gitignored files, lock home)
      # @param db [#start] the database service to bring up first
      def initialize(shell:, env:, checkout:, main_path:, runner: nil, db: nil, tty: nil)
        @shell = shell
        @env_config = EnvConfig.new(env)
        refuse_non_dev_env!
        @checkout = checkout
        @main_path = main_path
        @runner = runner || CommandRunner.new(shell: shell)
        @db = db || DbService.new(shell: shell, env: env)
        @tty = tty.nil? ? { stdin: $stdin.tty?, stdout: $stdout.tty? } : tty
      end

      # @return [Integer] the command's exit status
      def run(command_parts)
        raise Thor::Error, "No command given. Usage: bin/cli app run [--repo T] -- CMD..." if command_parts.empty?

        announce
        prepare
        runner.run_status(docker_run(command_parts, rails_env: env_config.env))
      end

      # @return [Integer] rspec's exit status
      def test(rspec_args)
        announce
        TestLock.new(path: File.join(main_path, LOCK_FILE)).synchronize(checkout.describe) do
          refuse_leftover_container!
          prepare
          args = rspec_args.empty? ? DEFAULT_TEST_ARGS : rspec_args
          script = "bin/rails db:test:prepare && bundle exec rspec #{Shellwords.join(args)}"
          runner.run_status(docker_run(["bash", "-c", script], rails_env: "test", name: TEST_CONTAINER))
        end
      end

      def docker_run(command_parts, rails_env:, name: nil)
        [
          "docker run --rm",
          *tty_flags,
          *("--name #{name}" if name),
          *flags.network,
          *flags.env(rails_env),
          *flags.volumes,
          env_config.app_image,
          Shellwords.join(command_parts)
        ]
      end

      private

      attr_reader :shell, :env_config, :checkout, :main_path, :runner, :db, :tty

      # Only the dev image runs mounted code. The prod image runs its baked-in
      # build (precompiled assets, production-only bundle), so a mounted
      # checkout would not match it. Refuse instead of silently running the
      # image's revision.
      def refuse_non_dev_env!
        return if env_config.short == "dev"

        raise Thor::Error,
              "bin/cli app run/test only supports the dev environment: it mounts a checkout, " \
              "and the #{env_config.env} image runs its built-in code. " \
              "Use `bin/cli app exec #{env_config.short} ...` for the production image."
      end

      def announce
        shell.say("Running in #{checkout.describe}")
      end

      def prepare
        sources.master_key_path
        sources.prepare!
        unless runner.image_exists?(env_config.app_image)
          raise Thor::Error, "App image #{env_config.app_image} is missing. Build it with `bin/cli app build`."
        end

        warn_gemfile_drift
        runner.ensure_network(env_config.network_name)
        db.start
      end

      def refuse_leftover_container!
        return if runner.container_status(TEST_CONTAINER) == "missing"

        raise Thor::Error,
              "Container #{TEST_CONTAINER} already exists, probably left by an earlier run. " \
              "Remove it with `docker rm -f #{TEST_CONTAINER}` and retry."
      end

      def warn_gemfile_drift
        local = File.join(checkout.path, "Gemfile.lock")
        return unless File.file?(local)

        output = runner.capture("docker run --rm --entrypoint sha256sum #{env_config.app_image} /rails/Gemfile.lock",
                                quiet: true)
        return if output.nil? || output.split.first == Digest::SHA256.file(local).hexdigest

        shell.say("Warning: #{local} differs from the one in #{env_config.app_image}; " \
                  "the image's gems may not match. Run `bin/cli app build` if gems changed.")
      end

      def tty_flags
        flags = []
        flags << "--interactive" if tty[:stdin]
        flags << "--tty" if tty[:stdin] && tty[:stdout]
        flags
      end

      def sources
        @sources ||= MountSources.new(checkout_path: checkout.path, main_path: main_path)
      end

      def flags
        @flags ||= ContainerFlags.new(env_config: env_config, checkout_path: checkout.path, sources: sources)
      end
    end
  end
end
