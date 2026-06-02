#!/usr/bin/env ruby

require_relative "../services/helpers"

module AppCLI
  module Services
    class MailService
      MAIL_CONTAINER = "mail".freeze
      MAIL_IMAGE = "isms/mailcatcher:0.10.0".freeze
      MAIL_PORT = "1080".freeze
      MAIL_HOST = "mail.workeverywhere.docker".freeze
      MAIL_ROUTER = "isms-mailcatcher".freeze

      def initialize(shell:)
        @runner = CommandRunner.new(shell: shell)
        @shell = shell
      end

      # docker run --rm --detach \
      #   --name mail \
      #   --publish 1080:1080 \
      #   --network network.docker-shared-services \
      #   --label traefik.enable=true \
      #   --label "traefik.http.routers.isms-mailcatcher.rule=Host(`mail.workeverywhere.docker`)" \
      #   --label traefik.http.routers.isms-mailcatcher.entrypoints=websecure \
      #   --label traefik.http.routers.isms-mailcatcher.tls=true \
      #   --label traefik.http.services.isms-mailcatcher.loadbalancer.server.port=1080 \
      #   --label traefik.docker.network=network.docker-shared-services \
      #   isms/mailcatcher:0.10.0
      def start
        runner.ensure_network(Services::NETWORK_NAME)

        status = runner.container_status(MAIL_CONTAINER)
        if status == "running"
          shell.say("Mail service already running.")
          return
        end

        if status != "missing"
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
          "--label traefik.enable=true",
          "--label 'traefik.http.routers.#{MAIL_ROUTER}.rule=Host(`#{MAIL_HOST}`)'",
          "--label traefik.http.routers.#{MAIL_ROUTER}.entrypoints=websecure",
          "--label traefik.http.routers.#{MAIL_ROUTER}.tls=true",
          "--label traefik.http.services.#{MAIL_ROUTER}.loadbalancer.server.port=1080",
          "--label traefik.docker.network=#{Services::NETWORK_NAME}",
          MAIL_IMAGE
        ]
      end
    end
  end
end
