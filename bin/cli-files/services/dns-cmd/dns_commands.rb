#!/usr/bin/env ruby

require "thor"
require_relative "../helpers"
require_relative "../../dns-cmd/dns_service"

module AppCLI
  module Services
    class DnsCommands < Thor
      include Thor::Actions

      desc "build", "Build the move-dns image (--force to rebuild)"
      method_option :force, type: :boolean, default: false
      def build
        dns.build(force: options[:force])
      end

      desc "start", "Start move-dns (*.#{DEV_DOMAIN} -> edge IP)"
      delegate :start, to: :dns

      desc "stop", "Stop move-dns"
      delegate :stop, to: :dns

      desc "restart", "Restart move-dns"
      def restart
        dns.stop
        dns.start
      end

      desc "logs", "View move-dns logs"
      delegate :logs, to: :dns

      desc "status", "Check move-dns status"
      def status
        say(CommandRunner.new(shell: self).format_status("#{APP_NAME} DNS", dns.status))
      end

      desc "check", "Verify container, host DNS delegate and live resolution"
      delegate :check, to: :dns

      desc "bootstrap", "Print the one-time root step routing the zone to move-dns"
      def bootstrap
        say(dns.bootstrap_script)
      end

      private

      def dns
        @dns ||= DnsService.new(shell: self)
      end
    end
  end
end
