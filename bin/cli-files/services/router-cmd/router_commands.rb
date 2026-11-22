#!/usr/bin/env ruby

require "thor"
require_relative "../helpers"
require_relative "../../router-cmd/router_service"

module AppCLI
  module Services
    class RouterCommands < Thor
      include Thor::Actions

      desc "install [ENV]", "Render the Traefik config for ENV (default dev) and ensure the certs"
      def install(env = nil)
        router(env).install
      end

      desc "start [ENV]", "Start move-router, routing the app of ENV (default dev)"
      def start(env = nil)
        router(env).start
      end

      desc "stop", "Stop move-router"
      delegate :stop, to: :router

      desc "restart [ENV]", "Restart move-router (reloads re-issued certs)"
      def restart(env = nil)
        router(env).stop
        router(env).start
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
        options[:rotate] ? router.rotate_certs : router.ensure_certs
      end

      private

      def router(env = nil)
        @router ||= RouterService.new(shell: self, env: env)
      end
    end
  end
end
