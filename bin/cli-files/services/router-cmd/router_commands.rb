#!/usr/bin/env ruby

require "thor"
require_relative "../helpers"
require_relative "../../router-cmd/router_service"

module AppCLI
  module Services
    class RouterCommands < Thor
      include Thor::Actions

      desc "install", "Render the Traefik config and ensure the TLS certificates"
      delegate :install, to: :router

      desc "start", "Start move-router (HTTPS edge on the edge IP)"
      delegate :start, to: :router

      desc "stop", "Stop move-router"
      delegate :stop, to: :router

      desc "restart", "Restart move-router (reloads re-issued certs)"
      def restart
        router.stop
        router.start
      end

      desc "logs", "View move-router logs"
      delegate :logs, to: :router

      desc "status", "Check move-router status"
      def status
        say(CommandRunner.new(shell: self).format_status("#{APP_NAME} Router", router.status))
      end

      desc "check", "Verify container, certs, a live TLS handshake and user trust"
      delegate :check, to: :router

      desc "trust", "Trust the dev root CA for this user (NSS: Chrome/Chromium/Brave)"
      delegate :trust, to: :router

      desc "certs", "Ensure the TLS material (--rotate replaces the root CA)"
      method_option :rotate, type: :boolean, default: false
      def certs
        options[:rotate] ? router.rotate_certs : router.install
      end

      private

      def router
        @router ||= RouterService.new(shell: self)
      end
    end
  end
end
