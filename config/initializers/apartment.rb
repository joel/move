# frozen_string_literal: true

# Multi-tenancy via ros-apartment: each Organization is a PostgreSQL schema
# (tenant). Auth tables and the tenant registry stay in the shared `public`
# schema. See AGENTS.md §1 and doc/phases/"Phase D1 - App Shell and Move Context".
#
# The subdomain Elevator (which resolves the tenant from the request host) is
# inserted separately so tenancy can be exercised from the console/tasks before
# the web middleware is wired up.
Apartment.configure do |config|
  # Shared, never tenant-scoped. Excluding a model does two things in the SQL
  # adapter: (1) keeps its table OUT of every tenant schema clone (pg_dump -T),
  # and (2) pins the AR model to the public connection regardless of the active
  # tenant. User is Rodauth's accounts table; Organization(+Membership) is the
  # tenant registry.
  config.excluded_models = %w[User Organization OrganizationMembership]

  # Always keep `public` on the search path so shared tables, the citext
  # extension, and the schema-qualified Rodauth key tables resolve from inside
  # any tenant. Rodauth's model-less key tables (user_remember_keys, …) are NOT
  # excluded, so they are cloned (empty) into each tenant; rodauth_main.rb
  # schema-qualifies every Rodauth table to `public` so auth never reads those
  # empty tenant copies.
  config.persistent_schemas = %w[public]

  # Clone tenant schemas from a pg_dump of `public` (requires schema_format :sql
  # and a pg_dump matching the server — see the postgresql-client-18 install).
  config.use_schemas = true
  config.use_sql = true

  # Physically keep the excluded_models tables OUT of every tenant schema
  # (not just routed to public). References to them from cloned tenant tables
  # stay `public.`-qualified, so e.g. posts.user_id still resolves to
  # public.users. This removes the empty-duplicate-table footgun entirely.
  config.pg_exclude_clone_tables = true

  # When cloning, Apartment rewrites every `public.X` qualifier to the new
  # tenant schema. The citext type lives only in public, so exclude it from
  # that rewrite — otherwise tenant tables reference a non-existent
  # `<tenant>.citext` type and creation fails.
  config.pg_excluded_names = %w[citext]

  # Tenants are the Organization slugs. Guarded so db:create/db:migrate work on a
  # fresh database before the organizations table exists.
  config.tenant_names = lambda do
    if ActiveRecord::Base.connection.table_exists?("organizations")
      Organization.pluck(:slug)
    else
      []
    end
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
    []
  end
end
