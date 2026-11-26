# frozen_string_literal: true

# Development only: the hostname zone and database of a worktree app started
# by `bin/cli app serve` (#869), read from the env vars it sets. With neither
# set, the values are main's (`move-easy.docker`, `move_development`).
#
#   MOVE_TENANT_ZONE   <wt>.wt.move-easy.docker  (apex move.<zone>, orgs <slug>.<zone>)
#   MOVE_DEV_DATABASE  move_development_wt_<wt>  (config/database.yml)
#
# Both are set together and must name the same <wt>, so a worktree app can't
# run on main's zone or main's database. Loaded by
# config/environments/development.rb only; production and test never read it.
# The bin/cli side is bin/cli-files/app-cmd/worktree_app.rb.
module DevWorktree
  class Error < StandardError; end

  DEFAULT_ZONE = "move-easy.docker"
  SHARED_DATABASE = "move_development"
  ZONE = /\A([a-z0-9](?:[a-z0-9-]{0,18}[a-z0-9])?)\.wt\.move-easy\.docker\z/
  DATABASE_PREFIX = "move_development_wt_"

  module_function

  def worktree?(env = ENV)
    !env["MOVE_TENANT_ZONE"].to_s.empty? || !env["MOVE_DEV_DATABASE"].to_s.empty?
  end

  # @return [String] the tenant zone; raises Error on an inconsistent pair
  def tenant_zone(env = ENV)
    return DEFAULT_ZONE unless worktree?(env)

    zone = env["MOVE_TENANT_ZONE"].to_s
    label = zone[ZONE, 1]
    raise Error, "MOVE_TENANT_ZONE=#{zone.inspect} is not <wt>.wt.move-easy.docker" unless label

    expected = database_for(label)
    database = env["MOVE_DEV_DATABASE"].to_s
    raise Error, "MOVE_DEV_DATABASE=#{database.inspect} must be #{expected} for #{zone}" unless database == expected

    zone
  end

  def apex_host(env = ENV) = "move.#{tenant_zone(env)}"

  def database_for(label) = "#{DATABASE_PREFIX}#{label.tr("-", "_")}"

  # Run once Rails has resolved its database config: a DATABASE_URL (from the
  # environment or a .env file) wins over config/database.yml and would put a
  # worktree app back on the shared database.
  def assert_database!(resolved, env = ENV)
    return unless worktree?(env)

    expected = env["MOVE_DEV_DATABASE"].to_s
    return if resolved == expected && resolved != SHARED_DATABASE

    raise Error, "Refusing to boot a worktree app on database #{resolved.inspect}: it must be #{expected} " \
                 "(is DATABASE_URL set?). #{SHARED_DATABASE} belongs to move-app-dev."
  end
end
