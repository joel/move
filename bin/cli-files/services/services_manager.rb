#!/usr/bin/env ruby

require_relative "helpers"
require_relative "../app-cmd/app_service"
require_relative "../db-cmd/db_service"
require_relative "../storage-cmd/storage_service"
require_relative "../dns-cmd/dns_service"
require_relative "../router-cmd/router_service"

module AppCLI
  module Services
    class ServicesManager
      attr_reader :app, :db, :storage, :dns, :router

      def initialize(shell:, env: nil)
        @app = AppService.new(shell: shell, env: env)
        @db = DbService.new(shell: shell, env: env)
        @storage = StorageService.new(shell: shell)
        @dns = DnsService.new(shell: shell)
        @router = RouterService.new(shell: shell, env: env)
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
        dns.build
        router.build
        db.build
        storage.build
        app.build
      end

      # The edge (dns + router) first: it only proxies, so it can come up before
      # its upstreams exist.
      def start_all
        start_dependencies
        app.start
      end

      # Everything app.start needs, without touching the app container.
      def start_dependencies
        dns.start
        router.start
        db.start
        storage.start
      end

      # Replaces the running app container. Every check that can fail (master
      # key, image, gems, dependencies, and Docker accepting the replacement)
      # runs while the old container still serves, so a failed restart leaves
      # it up.
      def restart_app
        app.prepare
        start_dependencies
        app.replace
      end

      def stop_all
        app.stop
        storage.stop
        db.stop
        router.stop
        dns.stop
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
