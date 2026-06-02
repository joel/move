#!/usr/bin/env ruby

require "thor"
require_relative "../helpers"
require_relative "../../mail-cmd/mail_service"

module AppCLI
  module Services
    class MailCommands < Thor
      include Thor::Actions

      desc "start", "Start the local mail service"
      delegate :start, to: :mail_service

      desc "stop", "Stop the local mail service"
      delegate :stop, to: :mail_service

      desc "logs", "View local mail service logs"
      delegate :logs, to: :mail_service

      desc "status", "Check local mail service status"
      def status
        say(runner.format_status("#{Services::APP_NAME} Mail", mail_service.status))
      end

      private

      def mail_service
        @mail_service ||= MailService.new(shell: self)
      end

      def runner
        @runner ||= CommandRunner.new(shell: self)
      end
    end
  end
end
