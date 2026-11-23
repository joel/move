#!/usr/bin/env ruby

require "shellwords"
require "thor"
require_relative "../services/helpers"

module AppCLI
  module Services
    # Every input the app container needs, resolved and validated in one
    # place. AppService#preflight runs it before `start` and before `restart`
    # stops anything, so a broken input never leaves move-app-dev down.
    #
    # - config/master.key and .env.<env> (MountSources: present, a file,
    #   readable, key not blank; worktree first, then the main checkout)
    # - the host side of every --volume (the checkout, the MySQL CA)
    # - the image: present (built if missing), with the project's Ruby
    # - the image's gems against the mounted Gemfile.lock (dev only)
    #
    # The Docker network is ensured in AppService#setup.
    class AppPreflight
      # @param build [#call] rebuilds the app image
      def initialize(env_config:, runner:, shell:, sources:, checkout_path:, build:)
        @env_config = env_config
        @runner = runner
        @shell = shell
        @sources = sources
        @checkout_path = checkout_path
        @build = build
      end

      def mount_sources!
        sources.master_key_path
        sources.env_file_path(env_config.env)
      end

      # Everything after #mount_sources! (which AppService#setup also runs).
      def image_and_volumes!
        volume_sources!
        image!
        bundle!
      end

      private

      attr_reader :env_config, :runner, :shell, :sources, :checkout_path, :build

      def volume_sources!
        raise Thor::Error, "#{checkout_path} is not a directory; it is mounted at /rails." if env_config.short == "dev" && !File.directory?(checkout_path)
        return unless env_config.mysql?

        ca = File.join(checkout_path, "certs/mysql/ca.pem")
        raise Thor::Error, "#{ca} is missing or unreadable; it is mounted into the container." unless File.readable?(ca)
      end

      def image!
        return ruby_version! if runner.image_exists?(env_config.app_image)

        shell.say("App image #{env_config.app_image} missing, building it first")
        build.call
      end

      def ruby_version!
        desired = env_config.ruby_version
        return if desired.nil?

        current = runner.capture(%(docker run --rm #{env_config.app_image} ruby -e "print RUBY_VERSION"),
                                 quiet: true).to_s.strip
        return if current == desired

        shell.say(if current.empty?
                    "Unable to detect Ruby version in #{env_config.app_image}; rebuilding image."
                  else
                    "Ruby version mismatch (#{current} != #{desired}); rebuilding image."
                  end)
        build.call
      end

      # The dev container runs the mounted checkout on the image's gems. A
      # checkout whose Gemfile.lock is ahead of the image (a worktree, or main
      # after a pull) would crash on boot.
      def bundle!
        return unless env_config.short == "dev"

        command = "docker run --rm --volume #{Shellwords.escape(checkout_path)}:/rails " \
                  "#{env_config.app_image} bundle check"
        return if runner.run(command, allow_failure: true)

        raise Thor::Error,
              "The gems in #{env_config.app_image} don't match #{checkout_path}/Gemfile.lock. " \
              "Run `bin/cli app build` (or `DOCKER_NAMESPACE=wt<n> bin/cli app build` for a private image), " \
              "then retry."
      end
    end
  end
end
