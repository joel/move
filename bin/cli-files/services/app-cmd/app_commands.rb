#!/usr/bin/env ruby

require "thor"
require_relative "../helpers"
require_relative "../../app-cmd/app_service"
require_relative "../../app-cmd/checkout_resolver"
require_relative "../../app-cmd/worktree_run"
require_relative "../../app-cmd/worktree_serve"
require_relative "../services_manager"

module AppCLI
  module Services
    class AppCommands < Thor
      include Thor::Actions

      REPO_OPTION_DESC = "Checkout to mount: a worktree branch or directory name, or a path " \
                         "(starts with /, . or ~). Default: the main checkout".freeze
      REPO_OPTION_DESC_SERVE = "Worktree to serve: a worktree branch or directory name, or a path " \
                               "(starts with /, . or ~). Not the main checkout".freeze

      desc "start [ENV]", "Start the application (runs setup/build/start for all services)"
      def start(env = nil)
        manager = ServicesManager.new(shell: self, env: env)
        manager.setup_all
        manager.build_all
        manager.start_all
      end

      desc "stop [ENV] [--repo T | --name W] [--drop-db]",
           "Stop the application container, or the worktree app `app serve` started (--repo / --name)"
      method_option :repo, type: :string, desc: "Worktree whose served app to stop (see `app serve`)"
      method_option :name, type: :string, desc: "Served worktree app to stop, by its name (move-app-wt-<name>)"
      method_option :drop_db, type: :boolean, default: false,
                              desc: "Also drop the worktree's own database (move_development_wt_<name>)"
      def stop(env = nil)
        return app_service(env).stop unless options[:repo] || options[:name]

        refuse_non_dev!(env, "stop --repo/--name")
        checkout = options[:repo] ? CheckoutResolver.new.resolve(options[:repo]) : nil
        worktree_serve(checkout).stop(drop_db: options[:drop_db])
      end

      desc "serve --repo T [--name W]",
           "Serve a worktree at https://move.<W>.wt.move-easy.docker, next to move-app-dev, on its own database"
      method_option :repo, type: :string, required: true, desc: REPO_OPTION_DESC_SERVE
      method_option :name, type: :string,
                           desc: "Name W for the app, zone and database (default: the worktree directory name)"
      def serve
        worktree_serve(CheckoutResolver.new.resolve(options[:repo])).serve
      end

      desc "logs [ENV]", "View application logs"
      def logs(env = nil)
        app_service(env).logs
      end

      desc "status [ENV]", "Output application status"
      def status(env = nil)
        say(runner.format_status("#{Services::APP_NAME} App", app_service(env).status))
      end

      desc "build [ENV]", "Build the application image"
      def build(env = nil)
        app_service(env).build
      end

      desc "prepare [ENV]", "Check every input of the app container (key, .env, volumes, image, gems, network)"
      def prepare(env = nil)
        app_service(env).preflight
      end

      desc "setup [ENV]", "Setup the application prerequisites"
      def setup(env = nil)
        app_service(env).setup
      end

      desc "teardown [ENV]", "Teardown the application image/container"
      def teardown(env = nil)
        app_service(env).teardown
      end

      desc "migrate [ENV]", "Run database migrations inside the application container"
      def migrate(env = nil)
        app_service(env).migrate
      end

      desc "schema_dump [ENV]", "Dump Rails schema from the application container"
      def schema_dump(env = nil)
        app_service(env).schema_dump
      end

      desc "exec [ENV] COMMAND", "Execute a command in the application container"
      def exec(*args)
        env, command_parts = parse_env_and_command(args)
        app_service(env).exec(command_parts)
      end

      desc "connect [ENV] [--repo T]", "Open a shell in the application container, or in a throwaway one for --repo"
      method_option :repo, type: :string, desc: REPO_OPTION_DESC
      def connect(env = nil)
        interactive(:connect, env)
      end

      desc "console [ENV] [--repo T]",
           "Open a Rails console in the application container, or in a throwaway one for --repo"
      method_option :repo, type: :string, desc: REPO_OPTION_DESC
      def console(env = nil)
        interactive(:console, env)
      end

      map "run" => :run_command
      desc "run [ENV] [--repo T] [--yes] -- CMD...", "Run a command in a throwaway app container for a checkout"
      method_option :repo, type: :string, desc: REPO_OPTION_DESC
      method_option :yes, type: :boolean, default: false,
                          desc: "Run a schema-changing db task (db:migrate, db:rollback, ...) from a worktree " \
                                "against the shared dev database"
      def run_command(*args)
        env, command_parts = parse_env_and_command(args)
        checkout = CheckoutResolver.new.resolve(options[:repo])
        exit(worktree_run(env, checkout).run(command_parts, confirmed: options[:yes]))
      end

      map "test" => :test_command
      desc "test [--repo T] [--system] [-- RSPEC_ARGS...]",
           "Run rspec (RAILS_ENV=test) in a throwaway container for a checkout"
      method_option :repo, type: :string, desc: REPO_OPTION_DESC
      method_option :system, type: :boolean, default: false,
                             desc: "Run spec/system with TEST_BROWSER=rack_test, as CI does"
      def test_command(*rspec_args)
        checkout = CheckoutResolver.new.resolve(options[:repo])
        exit(worktree_run(nil, checkout).test(rspec_args, system: options[:system]))
      end

      desc "rebuild [ENV]", "Rebuild and restart the application"
      def rebuild(env = nil)
        manager = ServicesManager.new(shell: self, env: env)
        manager.app.setup # key and .env before spending a build
        manager.app.build
        manager.restart_app
      end

      desc "restart [ENV]", "Restart the application"
      def restart(env = nil)
        ServicesManager.new(shell: self, env: env).restart_app
      end

      private

      def app_service(env)
        normalized_env = Services.normalize_env(env)
        @app_services ||= {}
        @app_services[normalized_env] ||= AppService.new(shell: self, env: normalized_env)
      end

      # No --repo: attach to the long-lived app container, as before.
      # --repo: a throwaway container for that checkout (dev only).
      def interactive(kind, env)
        return app_service(env).public_send(kind) unless options[:repo]

        checkout = CheckoutResolver.new.resolve(options[:repo])
        exit(worktree_run(env, checkout).interactive(kind))
      end

      def worktree_serve(checkout)
        app = WorktreeApp.for(checkout_path: checkout&.path, name: options[:name])
        main_path = CheckoutResolver.new.main_checkout.path
        WorktreeServe.new(shell: self, checkout: checkout, main_path: main_path, app: app)
      end

      def refuse_non_dev!(env, command)
        return if Services.short_env(Services.normalize_env(env)) == "dev"

        raise Thor::Error, "bin/cli app #{command} only supports the dev environment."
      end

      def worktree_run(env, checkout)
        main_path = CheckoutResolver.new.main_checkout.path
        WorktreeRun.new(shell: self, env: Services.normalize_env(env), checkout: checkout, main_path: main_path)
      end

      def parse_env_and_command(args)
        return [Services.normalize_env(nil), []] if args.empty?

        potential_env = Services.resolve_env_argument(args.first)
        if potential_env
          [potential_env, args[1..]]
        else
          [Services.normalize_env(nil), args]
        end
      end

      def runner
        @runner ||= CommandRunner.new(shell: self)
      end
    end
  end
end
