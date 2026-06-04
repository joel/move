#!/usr/bin/env ruby

require "fileutils"
require_relative "../services/helpers"

module AppCLI
  module Services
    class AppService
      def initialize(shell:, env:)
        @runner = CommandRunner.new(shell: shell)
        @shell = shell
        @env_config = EnvConfig.new(env)
      end

      def setup
        runner.ensure_network(env_config.network_name)
        ensure_master_key!
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
      end

      def start
        prepare

        if runner.container_running?(env_config.app_container)
          shell.say("Application already running.")
          return
        end

        FileUtils.rm_f(File.join(AppCLI::ROOT, "tmp/pids/server.pid"))

        runner.run(
          [
            "docker run --rm --detach",
            "--name #{env_config.app_container}",
            "--publish 8080:9292",
            *network_flags,
            *app_env_flags,
            *app_volume_flags,
            *traefik_flags,
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

      attr_reader :runner, :shell, :env_config

      def ensure_running!
        return if runner.container_running?(env_config.app_container)

        raise Thor::Error, "App container is not running. Start it with `bin/cli app start`."
      end

      def ensure_master_key!
        key_path = env_config.master_key_path
        return if File.exist?(key_path)

        raise Thor::Error, "Missing config/master.key. Please add it before starting the app."
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

      def ensure_sqlite_db_dir
        return unless env_config.sqlite3?

        FileUtils.mkdir_p(File.join(AppCLI::ROOT, "db"))
      end

      def app_env_flags
        flags = [
          "--env RAILS_MASTER_KEY=$(cat #{env_config.master_key_path})",
          "--env RAILS_ENV=#{env_config.env}",
          "--env RAILS_LOG_TO_STDOUT=true",
          "--env RAILS_SERVE_STATIC_FILES=true",
          "--env RAILS_ALLOW_ALL_HOSTS=true"
        ]

        flags << "--env BUNDLE_WITHOUT=production" if env_config.short == "dev"

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

      def app_volume_flags
        flags = []

        if env_config.mysql?
          flags << "--volume #{File.join(AppCLI::ROOT, "certs/mysql/ca.pem")}:/run/secrets/mysql-ca.pem:ro"
        end

        flags << "--volume #{AppCLI::ROOT}:/rails" if env_config.short == "dev"

        flags << "--volume #{File.join(AppCLI::ROOT, "db")}:/rails/db" if env_config.sqlite3?

        flags
      end

      def network_flags
        ["--network #{env_config.network_name}"]
      end

      def traefik_flags
        [
          "--label traefik.enable=true",
          "--label 'traefik.http.routers.#{env_config.traefik_router}.rule=#{env_config.traefik_rule}'",
          # Low priority so exact-host service routers (mail/storage/bucket) win
          # over the app's catch-all subdomain regexp.
          "--label traefik.http.routers.#{env_config.traefik_router}.priority=1",
          "--label traefik.http.routers.#{env_config.traefik_router}.entrypoints=websecure",
          "--label traefik.http.routers.#{env_config.traefik_router}.tls=true",
          "--label traefik.http.services.#{env_config.traefik_service}.loadbalancer.server.port=9292",
          "--label traefik.docker.network=#{env_config.network_name}"
        ]
      end

      def copy_schema_from_container(container_name)
        runner.run("docker cp #{container_name}:/rails/db/schema.rb db/schema.rb")
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
