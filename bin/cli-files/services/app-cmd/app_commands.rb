#!/usr/bin/env ruby

require "thor"
require_relative "../helpers"
require_relative "../../app-cmd/app_service"
require_relative "../services_manager"

module AppCLI
  module Services
    class AppCommands < Thor
      include Thor::Actions

      desc "start [ENV]", "Start the application (runs setup/build/start for all services)"
      def start(env = nil)
        manager = ServicesManager.new(shell: self, env: env)
        manager.setup_all
        manager.build_all
        manager.start_all
      end

      desc "stop [ENV]", "Stop the application container"
      def stop(env = nil)
        app_service(env).stop
      end

      desc "logs [ENV]", "View application logs"
      def logs(env = nil)
        app_service(env).logs
      end

      desc "status [ENV]", "Output application status"
      def status(env = nil)
        say(runner.format_status("#{Services::APP_NAME} App", app_service(env).status))
      end

      desc "build [ENV]", "Build the application image"
      def build(env = nil)
        app_service(env).build
      end

      desc "prepare [ENV]", "Prepare the application image and prerequisites"
      def prepare(env = nil)
        app_service(env).prepare
      end

      desc "setup [ENV]", "Setup the application prerequisites"
      def setup(env = nil)
        app_service(env).setup
      end

      desc "teardown [ENV]", "Teardown the application image/container"
      def teardown(env = nil)
        app_service(env).teardown
      end

      desc "connect [ENV]", "Connect to the application container"
      def connect(env = nil)
        app_service(env).connect
      end

      desc "console [ENV]", "Open a Rails console in the application container"
      def console(env = nil)
        app_service(env).console
      end

      desc "migrate [ENV]", "Run database migrations inside the application container"
      def migrate(env = nil)
        app_service(env).migrate
      end

      desc "schema_dump [ENV]", "Dump Rails schema from the application container"
      def schema_dump(env = nil)
        app_service(env).schema_dump
      end

      desc "exec [ENV] COMMAND", "Execute a command in the application container"
      def exec(*args)
        env, command_parts = parse_env_and_command(args)
        app_service(env).exec(command_parts)
      end

      desc "rebuild [ENV]", "Rebuild and restart the application"
      def rebuild(env = nil)
        service = app_service(env)
        service.stop
        service.build
        ServicesManager.new(shell: self, env: env).start_all
      end

      desc "restart [ENV]", "Restart the application"
      def restart(env = nil)
        service = app_service(env)
        service.stop
        ServicesManager.new(shell: self, env: env).start_all
      end

      private

      def app_service(env)
        normalized_env = Services.normalize_env(env)
        @app_services ||= {}
        @app_services[normalized_env] ||= AppService.new(shell: self, env: normalized_env)
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

      def runner
        @runner ||= CommandRunner.new(shell: self)
      end
    end
  end
end
