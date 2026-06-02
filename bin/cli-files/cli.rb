#!/usr/bin/env ruby

require "thor"
require_relative "services/helpers"
require_relative "services/app-cmd/app_commands"
require_relative "services/db-cmd/db_commands"
require_relative "services/mail-cmd/mail_commands"
require_relative "services/storage-cmd/storage_commands"
require_relative "services/services_commands"

Dir.chdir(AppCLI::ROOT) unless Dir.pwd == AppCLI::ROOT

module AppCLI
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "app SUBCOMMAND ...ARGS", "Application commands"
    subcommand "app", Services::AppCommands

    desc "db SUBCOMMAND ...ARGS", "Database commands"
    subcommand "db", Services::DbCommands

    desc "mail SUBCOMMAND ...ARGS", "Local mail service commands"
    subcommand "mail", Services::MailCommands

    desc "storage SUBCOMMAND ...ARGS", "Local SeaweedFS storage service commands"
    subcommand "storage", Services::StorageCommands

    desc "services SUBCOMMAND ...ARGS", "Service orchestration commands"
    subcommand "services", Services::ServicesCommands
  end
end

AppCLI::CLI.start(ARGV)
