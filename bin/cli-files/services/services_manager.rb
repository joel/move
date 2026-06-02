#!/usr/bin/env ruby

require_relative "helpers"
require_relative "../app-cmd/app_service"
require_relative "../db-cmd/db_service"
require_relative "../storage-cmd/storage_service"

module AppCLI
  module Services
    class ServicesManager
      attr_reader :app, :db, :storage

      def initialize(shell:, env: nil)
        @app = AppService.new(shell: shell, env: env)
        @db = DbService.new(shell: shell, env: env)
        @storage = StorageService.new(shell: shell)
      end

      # Active Storage points at SeaweedFS S3 in both dev and prod
      # (config/storage.yml + config/environments/*.rb), so storage is a
      # first-class service started alongside db/app rather than a manual
      # `bin/cli storage start` step.
      def setup_all
        db.setup
        storage.setup
        app.setup
      end

      def build_all
        db.build
        storage.build
        app.build
      end

      def start_all
        db.start
        storage.start
        app.start
      end

      def stop_all
        app.stop
        storage.stop
        db.stop
      end

      def restart_all
        stop_all
        start_all
      end

      def teardown_all
        app.teardown
        storage.teardown
        db.teardown
      end
    end
  end
end
