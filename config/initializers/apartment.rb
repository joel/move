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
  # Active Storage tables are shared in `public` (not per-tenant). Rails 8.1's
  # Active Storage controllers (e.g. the proxy) lease a fresh pool connection that
  # Apartment initializes to `public`, so per-tenant blobs 404'd. Keeping blobs/
  # attachments/variants in `public` makes them resolve regardless of the active
  # schema; the domain Media row stays per-tenant and references them by id.
  config.excluded_models = %w[
    User Organization OrganizationMembership
    ActiveStorage::Blob ActiveStorage::Attachment ActiveStorage::VariantRecord
  ]

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
  # tenant schema. Types/opclasses that live only in public must be excluded from
  # that rewrite — otherwise cloned tenant tables/indexes reference a
  # non-existent `<tenant>.X` and creation fails:
  #   - citext      — the citext extension type
  #   - vector      — pgvector column type on item_search_documents (D8)
  #   - *_ops       — opclasses behind the trigram + HNSW search indexes (D8)
  config.pg_excluded_names = %w[citext vector vector_cosine_ops gin_trgm_ops]

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
