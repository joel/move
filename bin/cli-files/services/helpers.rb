#!/usr/bin/env ruby

require "open3"
require "shellwords"
require "thor"
require "active_support/core_ext/module/delegation"

module AppCLI
  ROOT = File.expand_path("../../..", __dir__)

  module Services
    APP_NAME = "move".freeze
    DB_ADAPTER = "postgresql".freeze
    DOCKER_NAMESPACE = ENV.fetch("DOCKER_NAMESPACE", "workeverywhere").freeze
    NETWORK_NAME = "network.docker-shared-services".freeze
    DB_VOLUME_BASE = "#{APP_NAME}-data-volume".freeze
    APP_CONTAINER_BASE = "#{APP_NAME}-app".freeze
    DB_CONTAINER_BASE = "#{APP_NAME}-db".freeze
    APP_IMAGE_BASE = "#{DOCKER_NAMESPACE}/#{APP_NAME}-app".freeze
    WAIT_IMAGE = "workeverywhere/wait:2.12.1".freeze
    DB_IMAGES = {
      "mysql" => "mysql:latest",
      # pgvector/pgvector:pg18 = postgres:18 + the `vector` extension (D8 hybrid
      # search). Same PG18 cluster layout, so the existing data volume is reused.
      "postgresql" => "pgvector/pgvector:pg18"
    }.freeze
    DEFAULT_DB_PORTS = {
      "mysql" => 3306,
      "postgresql" => 5432
    }.freeze
    MYSQL_CERT_DIR = File.expand_path("certs/mysql", AppCLI::ROOT)
    TRAEFIK_ROUTER = "workeverywhere".freeze
    TRAEFIK_DOMAIN = "workeverywhere.docker".freeze
    SUPPORTED_ENVS = {
      "dev" => "development",
      "development" => "development",
      "prod" => "production",
      "production" => "production"
    }.freeze

    def self.normalize_env(env_arg)
      value = env_arg.to_s.strip
      return "development" if value.empty?

      normalized = SUPPORTED_ENVS[value.downcase]
      unless normalized
        raise Thor::Error,
              "Unsupported environment '#{env_arg}'. Use dev|development or prod|production."
      end

      normalized
    end

    def self.resolve_env_argument(env_arg)
      SUPPORTED_ENVS[env_arg.to_s.downcase]
    end

    def self.short_env(env_name)
      env_name.start_with?("prod") ? "prod" : "dev"
    end

    class EnvConfig
      attr_reader :env, :short

      def initialize(env_arg)
        @env = Services.normalize_env(env_arg)
        @short = Services.short_env(@env)
      end

      def app_name
        APP_NAME
      end

      def db_adapter
        DB_ADAPTER
      end

      def mysql?
        db_adapter == "mysql"
      end

      def postgresql?
        db_adapter == "postgresql"
      end

      def sqlite3?
        db_adapter == "sqlite3"
      end

      def app_container
        suffix_name(APP_CONTAINER_BASE)
      end

      def db_container
        return nil if sqlite3?

        suffix_name(DB_CONTAINER_BASE)
      end

      def network_name
        return NETWORK_NAME if short == "dev"

        suffix_name(NETWORK_NAME)
      end

      def db_volume
        return nil if sqlite3?

        suffix_name(DB_VOLUME_BASE)
      end

      def app_image
        tag = short == "dev" ? "latest" : short
        "#{APP_IMAGE_BASE}:#{tag}"
      end

      def wait_image
        WAIT_IMAGE
      end

      def db_image
        DB_IMAGES[db_adapter]
      end

      def db_port
        env_port = ENV.fetch("DB_PORT", nil)
        return env_port.to_s.strip unless env_port.nil? || env_port.strip.empty?

        default = DEFAULT_DB_PORTS[db_adapter]
        return nil unless default

        offset = short == "prod" ? 1 : 0
        (default + offset).to_s
      end

      def dockerfile_path
        File.join(AppCLI::ROOT, "dockerfiles", "Dockerfile-#{short}")
      end

      def ruby_version
        version_file = File.join(AppCLI::ROOT, ".ruby-version")
        return nil unless File.exist?(version_file)

        version = File.read(version_file).strip
        version = version.delete_prefix("ruby-")
        version.empty? ? nil : version
      end

      def master_key_path
        File.join(AppCLI::ROOT, "config/master.key")
      end

      def db_names
        base = env == "production" ? "#{APP_NAME}_production" : "#{APP_NAME}_development"
        [
          base,
          "#{base}_cache",
          "#{base}_queue",
          "#{base}_cable"
        ]
      end

      def sqlite_db_path
        File.join(AppCLI::ROOT, "db", "#{env}.sqlite3")
      end

      def traefik_host
        "#{APP_NAME}.#{TRAEFIK_DOMAIN}"
      end

      def traefik_domain
        TRAEFIK_DOMAIN
      end

      def traefik_router
        TRAEFIK_ROUTER
      end

      def traefik_service
        TRAEFIK_ROUTER
      end

      private

      def suffix_name(base)
        "#{base}-#{short}"
      end
    end

    class CommandRunner
      def initialize(shell:)
        @shell = shell
      end

      def say(message, *)
        if shell.respond_to?(:say)
          shell.say(message, *)
        else
          puts(message)
        end
      end

      def say_status(status, message)
        if shell.respond_to?(:say_status)
          shell.say_status(status, message)
        else
          puts("#{status}: #{message}")
        end
      end

      def run(command, quiet: false, allow_failure: false)
        normalized = normalize(command)
        say_status(:run, normalized) unless quiet

        success = Kernel.system(normalized)
        raise Thor::Error, "Command failed: #{normalized}" if !success && !allow_failure

        success
      end

      def capture(command, quiet: false)
        normalized = normalize(command)
        say_status(:run, normalized) unless quiet

        output, status = Open3.capture2e(normalized)
        return nil unless status.success?

        output
      end

      def image_exists?(image)
        system("docker image inspect #{image} >/dev/null 2>&1")
      end

      def container_status(name)
        output, status = Open3.capture2e("docker", "inspect", "-f", "{{.State.Status}}", name)
        status.success? ? output.strip : "missing"
      end

      def container_running?(name)
        container_status(name) == "running"
      end

      def ensure_network(name = NETWORK_NAME)
        return if system("docker network inspect #{name} >/dev/null 2>&1")

        run("docker network create #{name}")
      end

      def ensure_volume(name = DB_VOLUME_BASE)
        return if system("docker volume inspect #{name} >/dev/null 2>&1")

        run("docker volume create #{name}")
      end

      def ensure_mysql_certs
        return if Dir.exist?(MYSQL_CERT_DIR)

        run(File.join(AppCLI::ROOT, "bin/mysql.certificates.pre-build.sh"))
      end

      def network_exists?(name = NETWORK_NAME)
        system("docker network inspect #{Shellwords.escape(name)} >/dev/null 2>&1")
      end

      def network_in_use?(name = NETWORK_NAME)
        output, status = Open3.capture2e("docker", "network", "inspect", "-f", "{{json .Containers}}", name)
        return false unless status.success?

        containers = output.strip
        return false if containers.empty? || containers == "null"

        containers != "{}"
      end

      def volume_exists?(name = DB_VOLUME_BASE)
        system("docker volume inspect #{Shellwords.escape(name)} >/dev/null 2>&1")
      end

      def remove_network(name = NETWORK_NAME)
        run("docker network rm #{name}", allow_failure: true, quiet: true)
      end

      def remove_volume(name = DB_VOLUME_BASE)
        run("docker volume rm #{name}", allow_failure: true, quiet: true)
      end

      def remove_image(image)
        run("docker image rm #{image}", allow_failure: true, quiet: true)
      end

      def format_status(label, status)
        icon =
          case status
          when "running" then "✅"
          when "not_applicable" then "-"
          else "❌"
          end

        human =
          case status
          when "running" then "started"
          when "exited", "missing" then "stopped"
          when "not_applicable" then "N/A"
          else status
          end

        "#{label} #{icon} #{human}"
      end

      private

      attr_reader :shell

      def normalize(command)
        command.respond_to?(:join) ? command.join(" ") : command.to_s.gsub(/\s+/, " ").strip
      end
    end
  end
end
