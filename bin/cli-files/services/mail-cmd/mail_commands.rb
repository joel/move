#!/usr/bin/env ruby

require "thor"
require_relative "../helpers"
require_relative "../../mail-cmd/mail_service"

module AppCLI
  module Services
    class MailCommands < Thor
      include Thor::Actions

      desc "start", "Start the local mail service"
      def start
        mail_service.start
      end

      desc "stop", "Stop the local mail service"
      def stop
        mail_service.stop
      end

      desc "logs", "View local mail service logs"
      def logs
        mail_service.logs
      end

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
