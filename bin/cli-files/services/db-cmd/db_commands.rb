#!/usr/bin/env ruby

require "thor"
require_relative "../helpers"
require_relative "../../app-cmd/app_service"
require_relative "../../db-cmd/db_service"

module AppCLI
  module Services
    class DbCommands < Thor
      include Thor::Actions

      desc "start [ENV]", "Start the database"
      def start(env = nil)
        db_service(env).start
      end

      desc "prepare [ENV]", "Prepare the database (setup/start)"
      def prepare(env = nil)
        db_service(env).prepare
      end

      desc "stop [ENV]", "Stop the database"
      def stop(env = nil)
        db_service(env).stop
      end

      desc "logs [ENV]", "View database logs"
      def logs(env = nil)
        db_service(env).logs
      end

      desc "status [ENV]", "Check database status"
      def status(env = nil)
        say(runner.format_status("#{Services::APP_NAME} Db", db_service(env).status))
      end

      desc "build [ENV]", "Build (pull) the database image"
      def build(env = nil)
        db_service(env).build
      end

      desc "setup [ENV]", "Setup the database prerequisites"
      def setup(env = nil)
        db_service(env).setup
      end

      desc "teardown [ENV]", "Teardown the database"
      def teardown(env = nil)
        db_service(env).teardown
      end

      desc "connect [ENV]", "Connect to the database container shell"
      def connect(env = nil)
        db_service(env).connect
      end

      desc "console [ENV]", "Open database console"
      def console(env = nil)
        db_service(env).console
      end

      desc "exec [ENV] COMMAND", "Execute a command in the database container"
      def exec(*args)
        env, command_parts = parse_env_and_command(args)
        db_service(env).exec(command_parts)
      end

      desc "rebuild [ENV]", "Rebuild and restart the database"
      def rebuild(env = nil)
        service = db_service(env)
        service.stop
        service.build
        service.start
      end

      desc "restart [ENV]", "Restart the database"
      def restart(env = nil)
        service = db_service(env)
        service.stop
        service.start
      end

      desc "reset [ENV]", "Reset the database (drop, create, migrate, seed)"
      def reset(env = nil)
        normalized_env = Services.normalize_env(env)
        db_service(normalized_env).start
        AppService.new(shell: self, env: normalized_env)
                  .exec(%w[bin/rails db:drop db:create db:migrate db:seed], reuse_existing: false)
      end

      private

      def db_service(env)
        normalized_env = Services.normalize_env(env)
        @db_services ||= {}
        @db_services[normalized_env] ||= DbService.new(shell: self, env: normalized_env)
      end

      def runner
        @runner ||= CommandRunner.new(shell: self)
      end

      def parse_env_and_command(args)
        return [Services.normalize_env(nil), []] if args.empty?

        potential_env = Services.resolve_env_argument(args.first)
        if potential_env
          [potential_env, args[1..]]
        else
          [Services.normalize_env(nil), args]
        end
      end
    end
  end
end
