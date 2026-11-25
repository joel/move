#!/usr/bin/env ruby

require "shellwords"
require "thor"
require_relative "../services/helpers"
require_relative "../db-cmd/db_service"
require_relative "../router-cmd/router_service"
require_relative "../router-cmd/worktree_route"
require_relative "app_preflight"
require_relative "container_flags"
require_relative "mount_sources"
require_relative "readiness_check"
require_relative "test_lock"
require_relative "worktree_app"

module AppCLI
  module Services
    # `bin/cli app serve --repo T` and `app stop --repo T`: a second, routed
    # app container per worktree, next to move-app-dev, with its own hostname
    # zone and its own dev database (see WorktreeApp). Dev only.
    class WorktreeServe
      MAX_APPS = 3
      LOCK_FILE = "tmp/app-serve.lock".freeze
      LOCK_BUSY = "Refused: another `bin/cli app serve` or `app stop --repo` is in progress".freeze
      # The entrypoint only prepares the database for `./bin/rails server`, so
      # serve does it first, in a throwaway container. db:create runs in its
      # own process: Apartment initialises at boot and skips that when the
      # database is missing, and the seeds' tenant clone then rewrites the
      # public-schema foreign keys (to users) into the tenant. db:prepare then
      # loads the worktree's structure.sql into the empty database and seeds
      # it, db:migrate also brings Apartment tenant schemas up to date, and
      # tailwindcss:build writes the gitignored stylesheet a fresh worktree lacks.
      PREPARE = "bin/rails db:create && bin/rails db:prepare && bin/rails db:migrate && " \
                "bin/rails tailwindcss:build".freeze
      # The pid file stays in the container: the checkout's tmp/pids is the
      # one move-app-dev uses when it serves the same checkout.
      SERVER = "bin/rails s -p 9292 -b 0.0.0.0 -P /tmp/server.pid".freeze

      # @param checkout [Checkout, nil] the worktree to serve (nil only for `stop --name`)
      # @param main_path [String] the main checkout (fallback for gitignored files, lock home)
      def initialize(shell:, checkout:, main_path:, app:, runner: nil, db: nil, route: nil, router: nil)
        @shell = shell
        @checkout = checkout
        @main_path = main_path
        @app = app
        @env_config = EnvConfig.new("development")
        @runner = runner || CommandRunner.new(shell: shell)
        @db = db || DbService.new(shell: shell, env: "development")
        @route = route || WorktreeRoute.new(app: app)
        @router = router || RouterService.new(shell: shell)
      end

      def serve
        refuse_main_checkout!
        refuse_shared_database!
        announce
        preflight
        with_lock do
          # First, so a re-serve never reports a URL nothing routes to.
          refuse_router_down!
          next already_serving if serving_this_checkout?

          refuse_other_checkout!
          refuse_over_cap!
          start
        end
      end

      # Removes the container and the router entry; the database only with
      # drop_db. Without a checkout (`stop --name W`, e.g. for a worktree
      # already deleted), whatever container has that name is stopped.
      def stop(drop_db: false)
        with_lock do
          refuse_other_checkout! if checkout
          runner.run("docker rm --force #{app.container}", allow_failure: true) if present?(app.container)
          route.remove!
          shell.say("Stopped #{app.container}; removed its route (#{app.url}).")
          drop_database if drop_db
        end
      end

      private

      attr_reader :shell, :checkout, :main_path, :app, :env_config, :runner, :db, :route, :router

      def refuse_main_checkout!
        return unless checkout.main?

        raise Thor::Error, "#{checkout.path} is the main checkout, which move-app-dev serves " \
                           "(`bin/cli app start`). Serve a worktree with `bin/cli app serve --repo <worktree>`."
      end

      # The point of a served worktree: its migrations, seeds and console
      # writes never reach move_development. config/dev_worktree.rb checks the
      # same thing again once Rails has resolved its database config.
      def refuse_shared_database!
        shared = env_config.db_names
        return if app.database.start_with?(WorktreeApp::DATABASE_PREFIX) && shared.none?(app.database)

        raise Thor::Error, "Refusing to serve #{checkout.path} on #{app.database}: it would share a database " \
                           "with #{env_config.app_container}."
      end

      def announce
        shell.say("Serving #{checkout.describe}")
        shell.say("Database: #{app.database} (its own; #{env_config.db_names.first} is not touched)")
      end

      def preflight
        checks = AppPreflight.new(env_config: env_config, runner: runner, shell: shell, sources: sources,
                                  checkout_path: checkout.path, build: method(:missing_image!))
        checks.mount_sources!
        checks.image_and_volumes!
        sources.prepare!
      end

      def missing_image!
        raise Thor::Error, "App image #{env_config.app_image} is missing or has the wrong Ruby. " \
                           "Build it with `bin/cli app build`."
      end

      def with_lock(&)
        holder = checkout ? checkout.describe : app.container
        TestLock.new(path: File.join(main_path, LOCK_FILE), busy: LOCK_BUSY).synchronize(holder, &)
      end

      def start
        runner.ensure_network(env_config.network_name)
        db.start
        runner.run(["docker rm --force #{app.container}"], allow_failure: true, quiet: true) if present?(app.container)
        prepare_database!
        runner.run(["docker run --detach", "--name #{app.container}", *container_args(SERVER)])
        await_ready!
        route.write!
        announce_urls
      end

      # SKIP_TEST_DATABASE: in development, db:create and db:prepare also act
      # on the test database, the move_test every worktree shares under the
      # `app test` lock.
      def prepare_database!
        status = runner.run_status(["docker run --rm", "--env SKIP_TEST_DATABASE=true",
                                    *container_args("bash -c #{Shellwords.escape(PREPARE)}")])
        return if status.zero?

        raise Thor::Error, "Preparing #{app.database} failed (exit #{status}); nothing was started."
      end

      def await_ready!
        readiness = ReadinessCheck.new(runner: runner, shell: shell, timeout: ReadinessCheck.timeout)
        return if readiness.ready?(app.container)

        logs = runner.capture("docker logs --tail 40 #{app.container}", quiet: true).to_s
        runner.run("docker rm --force #{app.container}", allow_failure: true, quiet: true)
        raise Thor::Error, "#{app.container} (#{checkout.path}) did not answer /up. Its last log lines:\n" \
                           "#{logs.strip}\n\nIt was removed; main's move-app-dev was not touched."
      end

      def container_args(command)
        [
          *flags.network,
          *flags.env("development"),
          *app.env_flags,
          *flags.volumes,
          env_config.app_image,
          command
        ]
      end

      def already_serving
        route.write!
        shell.say("#{app.container} already serves #{checkout.path}.")
        announce_urls
      end

      def announce_urls
        shell.say("Serving #{checkout.path} at #{app.url}")
        shell.say("Org hosts: https://<slug>.#{app.zone}. Stop it with `bin/cli app stop --repo #{checkout.path}`.")
      end

      def serving_this_checkout?
        runner.container_running?(app.container) && mounted_checkout == File.expand_path(checkout.path)
      end

      # Two worktrees whose directory names give the same label would share
      # the container and the database.
      def refuse_other_checkout!
        mounted = mounted_checkout
        return if mounted.nil? || mounted == File.expand_path(checkout.path)

        raise Thor::Error, "#{app.container} serves #{mounted}, not #{checkout.path}; both would use " \
                           "#{app.database}. Pick another name with --name W."
      end

      def refuse_over_cap!
        others = served_apps - [app.container]
        return if others.size < MAX_APPS

        raise Thor::Error, "Refused: #{others.size} worktree apps already run (#{others.join(", ")}); the cap is " \
                           "#{MAX_APPS}. Stop one with `bin/cli app stop --name <wt>`."
      end

      def refuse_router_down!
        return if runner.container_running?(RouterService::CONTAINER)

        raise Thor::Error, "move-router is not running, so #{app.url} would not resolve to an app. " \
                           "Start it with `bin/cli router start`."
      end

      # Running ones only: a crashed app's leftover container doesn't serve,
      # and `serve` replaces it when it is this app's.
      def served_apps
        output = runner.capture("docker ps --filter name=^#{WorktreeApp::CONTAINER_PREFIX} " \
                                "--format '{{.Names}}'", quiet: true)
        output.to_s.split.grep(/\A#{Regexp.escape(WorktreeApp::CONTAINER_PREFIX)}/o).sort
      end

      def present?(name) = runner.container_status(name) != "missing"

      # The host checkout mounted at /rails, nil when there is no container.
      def mounted_checkout
        return unless present?(app.container)

        format = %q('{{range .Mounts}}{{if eq .Destination "/rails"}}{{.Source}}{{end}}{{end}}')
        source = runner.capture("docker inspect --format #{format} #{app.container}", quiet: true).to_s.strip
        source.empty? ? nil : File.expand_path(source)
      end

      def drop_database
        db_container = env_config.db_container
        runner.run("docker exec #{db_container} dropdb --username postgres --if-exists #{app.database}")
        shell.say("Dropped #{app.database}.")
      end

      def sources
        @sources ||= MountSources.new(checkout_path: checkout.path, main_path: main_path)
      end

      def flags
        @flags ||= ContainerFlags.new(env_config: env_config, checkout_path: checkout.path, sources: sources)
      end
    end
  end
end
