#!/usr/bin/env ruby

require_relative "../services/helpers"

module AppCLI
  module Services
    class DbService
      def initialize(shell:, env:)
        @runner = CommandRunner.new(shell: shell)
        @shell = shell
        @env_config = EnvConfig.new(env)
      end

      def setup
        return if env_config.sqlite3?

        runner.ensure_network(env_config.network_name)
        runner.ensure_volume(env_config.db_volume)
        runner.ensure_mysql_certs if env_config.mysql?
      end

      def build
        return sqlite_notice("SQLite does not require a database image.") if env_config.sqlite3?

        if runner.image_exists?(env_config.db_image)
          shell.say("Database image #{env_config.db_image} already present, skipping pull.")
        else
          shell.say("Pulling #{env_config.db_image} image")
          runner.run("docker pull #{env_config.db_image}")
        end
      end

      def start
        return sqlite_notice("SQLite uses local files; no container to start.") if env_config.sqlite3?

        setup

        if runner.container_running?(env_config.db_container)
          shell.say("Database already running.")
          ensure_databases
          return
        end

        db_port = env_config.db_port
        shell.say("Starting database on port #{db_port}") if db_port

        runner.run(db_run_command(db_port))
        wait_for_db_ready
        ensure_databases
      end

      def prepare
        start
      end

      def stop
        return sqlite_notice("SQLite uses local files; no container to stop.") if env_config.sqlite3?

        if runner.container_running?(env_config.db_container)
          shell.say("Stopping database container")
          runner.run("docker stop #{env_config.db_container}")
        else
          shell.say("Database not running, skipping stop.")
        end
      end

      def teardown
        return sqlite_notice("SQLite uses local files; no teardown needed.") if env_config.sqlite3?

        stop
        shell.say("Removing network and volume")

        if runner.network_exists?(env_config.network_name)
          if runner.network_in_use?(env_config.network_name)
            shell.say("Docker network '#{env_config.network_name}' has active endpoints, skipping removal.")
          else
            runner.remove_network(env_config.network_name)
          end
        else
          shell.say("Docker network '#{env_config.network_name}' not found, skipping removal.")
        end

        if runner.volume_exists?(env_config.db_volume)
          runner.remove_volume(env_config.db_volume)
        else
          shell.say("Docker volume '#{env_config.db_volume}' not found, skipping removal.")
        end
      end

      def logs(follow: true)
        return sqlite_notice("SQLite does not have container logs.") if env_config.sqlite3?

        args = follow ? "-f" : ""
        runner.run("docker logs #{args} #{env_config.db_container}")
      end

      def status
        return "not_applicable" if env_config.sqlite3?

        runner.container_status(env_config.db_container)
      end

      def console
        if env_config.sqlite3?
          runner.run("sqlite3 #{env_config.sqlite_db_path}")
          return
        end

        ensure_running!
        if env_config.postgresql?
          runner.run("docker exec -it #{env_config.db_container} psql -U postgres")
        else
          runner.run("docker exec -it #{env_config.db_container} mysql -u root")
        end
      end

      def connect
        return sqlite_notice("SQLite uses local files; no container shell available.") if env_config.sqlite3?

        ensure_running!
        runner.run("docker exec -it #{env_config.db_container} bash")
      end

      def exec(command_parts)
        if env_config.sqlite3?
          raise Thor::Error, "No command provided for db exec." if command_parts.empty?

          sql = command_parts.join(" ")
          runner.run("sqlite3 #{env_config.sqlite_db_path} #{Shellwords.escape(sql)}")
          return
        end

        ensure_running!
        raise Thor::Error, "No command provided for db exec." if command_parts.empty?

        escaped = command_parts.map { |p| Shellwords.escape(p) }.join(" ")
        runner.run(%(docker exec -it #{env_config.db_container} bash -c #{Shellwords.escape(escaped)}))
      end

      private

      attr_reader :runner, :shell, :env_config

      def ensure_running!
        return if runner.container_running?(env_config.db_container)

        raise Thor::Error, "Database container is not running. Start it with `bin/cli db start`."
      end

      def ensure_databases
        return unless env_config.mysql? || env_config.postgresql?

        ensure_running!

        missing = env_config.db_names.reject do |db_name|
          database_exists?(db_name)
        end

        if missing.empty?
          shell.say("All expected databases exist.")
        else
          create_missing_databases(missing)
        end
      rescue StandardError => e # rubocop:disable Move/BroadRescue -- dev CLI best-effort DB check
        shell.say("Could not verify databases: #{e.message}")
      end

      def database_exists?(db_name)
        if env_config.postgresql?
          query = "SELECT 1 FROM pg_database WHERE datname='#{db_name}';"
          output = runner.capture(
            %(docker exec #{env_config.db_container} psql -U postgres -tAc #{Shellwords.escape(query)}),
            quiet: true
          )
          output&.include?("1")
        else
          db_user = mysql_user
          query = %(SHOW DATABASES LIKE "#{db_name}";)
          output = runner.capture(
            %(docker exec #{env_config.db_container} mysql --protocol=TCP -h 127.0.0.1 -P 3306 -u #{db_user} -N -e '#{query}'),
            quiet: true
          )
          output&.include?(db_name)
        end
      end

      def create_missing_databases(missing)
        if env_config.postgresql?
          missing.each do |db|
            statement = %(CREATE DATABASE "#{db}";)
            runner.run(
              %(docker exec #{env_config.db_container} psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c #{Shellwords.escape(statement)}),
              allow_failure: true
            )
          end
        else
          db_user = mysql_user
          statements = missing.map { |db| "CREATE DATABASE IF NOT EXISTS `#{db}`;" }.join(" ")
          runner.run(
            %(docker exec #{env_config.db_container} mysql --protocol=TCP -h 127.0.0.1 -P 3306 -u #{db_user} -N -e '#{statements}'),
            allow_failure: true
          )
        end

        shell.say("Ensured databases exist: #{missing.join(", ")}")
      end

      def wait_for_db_ready
        if env_config.postgresql?
          wait_for_postgres
        else
          wait_for_mysql
        end
      end

      def wait_for_mysql
        max_attempts = 30
        shell.say("Waiting for MySQL in '#{env_config.db_container}' to be ready...")

        max_attempts.times do |attempt|
          ok = system(
            %(docker exec #{env_config.db_container} mysqladmin ping --protocol=TCP -h 127.0.0.1 -P 3306 -u root --silent)
          )
          if ok
            shell.say("MySQL is ready!")
            return
          end

          shell.say("Attempt #{attempt + 1}/#{max_attempts}: Not ready yet. Retrying in 1s...")
          sleep 1
        end

        raise Thor::Error, "MySQL did not become ready after #{max_attempts} attempts."
      end

      def wait_for_postgres
        max_attempts = 30
        shell.say("Waiting for PostgreSQL in '#{env_config.db_container}' to be ready...")

        max_attempts.times do |attempt|
          ok = system(
            %(docker exec #{env_config.db_container} pg_isready -U postgres -h 127.0.0.1 -p 5432 >/dev/null 2>&1)
          )
          if ok
            shell.say("PostgreSQL is ready!")
            return
          end

          shell.say("Attempt #{attempt + 1}/#{max_attempts}: Not ready yet. Retrying in 1s...")
          sleep 1
        end

        raise Thor::Error, "PostgreSQL did not become ready after #{max_attempts} attempts."
      end

      def db_run_command(db_port)
        if env_config.postgresql?
          [
            "docker run --rm --detach",
            "--name #{env_config.db_container}",
            "--env POSTGRES_HOST_AUTH_METHOD=trust",
            "--network #{env_config.network_name}",
            # postgres:18+ stores data in a major-version subdirectory; mount the
            # parent (/var/lib/postgresql), not /var/lib/postgresql/data. Matches
            # the prod accessory mount in config/deploy.yml.
            "--volume #{env_config.db_volume}:/var/lib/postgresql",
            ("--publish #{db_port}:5432" if db_port),
            env_config.db_image
          ].compact
        else
          [
            "docker run --rm --detach",
            "--name #{env_config.db_container}",
            "--env MYSQL_ALLOW_EMPTY_PASSWORD=yes",
            "--network #{env_config.network_name}",
            "--volume #{env_config.db_volume}:/var/lib/mysql",
            "--volume #{File.join(AppCLI::ROOT, "certs/mysql/ca.pem")}:/etc/mysql/certs/ca.pem:ro",
            "--volume #{File.join(AppCLI::ROOT, "certs/mysql/server-cert.pem")}:/etc/mysql/certs/server-cert.pem:ro",
            "--volume #{File.join(AppCLI::ROOT, "certs/mysql/server-key.pem")}:/etc/mysql/certs/server-key.pem:ro",
            "--volume #{File.join(AppCLI::ROOT, "config/mysql/ssl.cnf")}:/etc/mysql/conf.d/ssl.cnf:ro",
            "--volume #{File.join(AppCLI::ROOT, "config/mysql/init.sql")}:/docker-entrypoint-initdb.d/001-init.sql:ro",
            ("--publish #{db_port}:3306" if db_port),
            env_config.db_image
          ].compact
        end
      end

      def mysql_user
        Shellwords.escape(ENV.fetch("MYSQL_USER", "root"))
      end

      def sqlite_notice(message)
        shell.say(message)
      end
    end
  end
end
