#!/usr/bin/env ruby

require_relative "../services/helpers"

module AppCLI
  module Services
    class MailService
      MAIL_CONTAINER = "mail".freeze
      # The upstream author's image; the old isms/mailcatcher tag was a local V1 build.
      MAIL_IMAGE = "sj26/mailcatcher:v0.10.0".freeze
      MAIL_PORT = "1080".freeze

      def initialize(shell:)
        @runner = CommandRunner.new(shell: shell)
        @shell = shell
      end

      # Routed at https://mail.move-easy.docker by move-router (router_config.rb).
      def start
        runner.ensure_network(Services::NETWORK_NAME)

        status = runner.container_status(MAIL_CONTAINER)
        if status == "running"
          shell.say("Mail service already running.")
          return
        elsif status != "missing"
          shell.say("Removing existing mail service container (status: #{status}).")
          runner.run("docker rm #{MAIL_CONTAINER}", allow_failure: true)
        end

        runner.run(mail_run_command)
      end

      def stop
        if runner.container_running?(MAIL_CONTAINER)
          shell.say("Stopping mail service container")
          runner.run("docker stop #{MAIL_CONTAINER}")
        else
          shell.say("Mail service not running, skipping stop.")
        end
      end

      def logs(follow: true)
        args = follow ? "-f" : ""
        runner.run("docker logs #{args} #{MAIL_CONTAINER}")
      end

      def status
        runner.container_status(MAIL_CONTAINER)
      end

      private

      attr_reader :runner, :shell

      def mail_run_command
        [
          "docker run --rm --detach",
          "--name #{MAIL_CONTAINER}",
          "--publish #{MAIL_PORT}:1080",
          "--network #{Services::NETWORK_NAME}",
          MAIL_IMAGE
        ]
      end
    end
  end
end
