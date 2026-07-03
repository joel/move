# frozen_string_literal: true

# Schema-derived model signatures (sig/rbs_rails/) — see doc/project/type-checking.md.
# `bin/rails rbs_rails:all` regenerates them (needs the booted app + DB, like
# db:schema:dump); CI re-runs it in the packwerk job and fails on drift, the way
# RailsSchemaUpToDate guards structure.sql. rbs_rails is a :development-group gem
# (require: false) and absent from the production image (BUNDLE_WITHOUT), so the
# task quietly doesn't exist there.
begin
  require "rbs_rails/rake_task"

  # Behavior (signature dir, ignored models) is configured in config/rbs_rails.rb.
  RbsRails::RakeTask.new
rescue LoadError
  # dev-only tooling; nothing to define in production
end
