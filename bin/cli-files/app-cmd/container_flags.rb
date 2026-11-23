#!/usr/bin/env ruby

require "shellwords"
require_relative "../services/helpers"
require_relative "mount_sources"

module AppCLI
  module Services
    # The `docker run` env and volume flags for an app container serving one
    # checkout. Shared by the long-lived dev container and the throwaway
    # `app run` / `app test` containers.
    class ContainerFlags
      def initialize(env_config:, checkout_path:, sources:)
        @env_config = env_config
        @checkout_path = checkout_path
        @sources = sources
      end

      def env(rails_env = env_config.env)
        flags = [
          "--env RAILS_MASTER_KEY=$(cat #{Shellwords.escape(sources.master_key_path)})",
          "--env RAILS_ENV=#{rails_env}",
          "--env RAILS_LOG_TO_STDOUT=true",
          "--env RAILS_SERVE_STATIC_FILES=true",
          "--env RAILS_ALLOW_ALL_HOSTS=true"
        ]

        # docker run --env-file fails if the file is absent (e.g. a checkout that
        # hasn't run bin/setup), so only pass it when one is found.
        env_file = sources.env_file_path(rails_env)
        flags << "--env-file #{Shellwords.escape(env_file)}" if env_file

        flags << "--env BUNDLE_WITHOUT=production" if env_config.short == "dev"
        flags.concat(db_flags)
      end

      def volumes
        flags = []

        flags << "--volume #{File.join(checkout_path, "certs/mysql/ca.pem")}:/run/secrets/mysql-ca.pem:ro" if env_config.mysql?
        flags << "--volume #{Shellwords.escape(checkout_path)}:/rails" if env_config.short == "dev"
        flags << "--volume #{File.join(checkout_path, "db")}:/rails/db" if env_config.sqlite3?

        flags
      end

      def network
        ["--network #{env_config.network_name}"]
      end

      private

      attr_reader :env_config, :checkout_path, :sources

      def db_flags
        flags = []
        if env_config.mysql? || env_config.postgresql?
          db_port = env_config.db_port
          flags << "--env DB_HOST=#{env_config.db_container}"
          flags << "--env DB_PORT=#{db_port}" if db_port
        end

        if env_config.mysql?
          flags << "--env MYSQL_USER=root"
          flags << "--env MYSQL_PASSWORD=\"\""
        end
        flags
      end
    end
  end
end
