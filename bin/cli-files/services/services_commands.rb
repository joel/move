#!/usr/bin/env ruby

require "thor"
require_relative "helpers"
require_relative "services_manager"

module AppCLI
  module Services
    class ServicesCommands < Thor
      include Thor::Actions

      desc "list", "List all services"
      def list
        say("app")
        say("db")
        say("storage")
      end

      desc "status [ENV]", "Check status of services"
      def status(env = nil)
        manager = manager(env)
        {
          "#{Services::APP_NAME} Db" => manager.db.status,
          "#{Services::APP_NAME} Storage" => manager.storage.status,
          "#{Services::APP_NAME} App" => manager.app.status
        }.each do |label, service_status|
          say(runner.format_status(label, service_status))
        end
      end

      desc "setup [ENV]", "Setup services"
      def setup(env = nil)
        manager(env).setup_all
      end

      desc "build [ENV]", "Build services"
      def build(env = nil)
        manager(env).build_all
      end

      desc "start [ENV]", "Start services"
      def start(env = nil)
        manager(env).start_all
      end

      desc "teardown [ENV]", "Teardown services"
      def teardown(env = nil)
        manager(env).teardown_all
      end

      desc "restart [ENV]", "Restart services"
      def restart(env = nil)
        manager(env).restart_all
      end

      desc "stop [ENV]", "Stop services"
      def stop(env = nil)
        manager(env).stop_all
      end

      private

      def manager(env)
        ServicesManager.new(shell: self, env: env)
      end

      def runner
        @runner ||= CommandRunner.new(shell: self)
      end
    end
  end
end
