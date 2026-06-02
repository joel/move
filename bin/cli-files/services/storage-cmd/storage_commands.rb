#!/usr/bin/env ruby

require "thor"
require_relative "../helpers"
require_relative "../../storage-cmd/storage_service"

module AppCLI
  module Services
    class StorageCommands < Thor
      include Thor::Actions

      desc "start", "Start the local SeaweedFS storage service"
      delegate :start, to: :storage_service

      desc "stop", "Stop the local SeaweedFS storage service"
      delegate :stop, to: :storage_service

      desc "logs", "View SeaweedFS storage service logs"
      delegate :logs, to: :storage_service

      desc "create_bucket", "Ensure the Active Storage bucket exists"
      def create_bucket
        storage_service.ensure_bucket
      end

      desc "status", "Check SeaweedFS storage service status"
      def status
        say(runner.format_status("#{Services::APP_NAME} Storage",
                                 storage_service.status))
      end

      private

      def storage_service
        @storage_service ||= StorageService.new(shell: self)
      end

      def runner
        @runner ||= CommandRunner.new(shell: self)
      end
    end
  end
end
