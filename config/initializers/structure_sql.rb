# frozen_string_literal: true

# Keep db/structure.sql dumps deterministic under Apartment.
#
# Two sources of churn in :sql mode, both fixed here by wrapping the PostgreSQL
# structure dump (the adapter method, so it also covers the dump db:migrate runs
# internally — which bypasses the db:schema:dump rake task):
#
#   1. Tenant-schema leakage. With the default dump_schemas and no
#      schema_search_path in database.yml, pg_dump dumps EVERY schema, so any
#      Apartment tenant schemas that happen to exist (acme, …) get baked into the
#      public template. We exclude every non-public, non-system schema via
#      --exclude-schema. (Note: --schema=public is NOT usable here — it emits
#      `CREATE SCHEMA public` and drops `CREATE EXTENSION citext`, breaking load.)
#
#   2. Trailing search_path line. Rails appends `SET search_path TO
#      <connection search_path>;`, whose value Apartment varies between dumps
#      ("public" / "public", "public" / "$user", public). We normalize it.
module DeterministicStructureSearchPath
  CANONICAL_SEARCH_PATH = %(SET search_path TO "public";)

  def structure_dump(filename, extra_flags = nil)
    super(filename, Array(extra_flags) + tenant_exclude_flags)
    normalize_search_path(filename)
  end

  private

  def tenant_exclude_flags
    non_public_schemas.map { |schema| "--exclude-schema=#{schema}" }
  end

  def non_public_schemas
    ActiveRecord::Base.connection.select_values(<<~SQL.squish)
      SELECT nspname FROM pg_namespace
      WHERE nspname NOT IN ('public', 'information_schema')
        AND nspname NOT LIKE 'pg\\_%'
    SQL
  rescue StandardError # rubocop:disable Move/BroadRescue -- DB may be unavailable at load/dump time
    []
  end

  def normalize_search_path(filename)
    return unless File.exist?(filename)

    sql = File.read(filename)
    normalized = sql.gsub(/^SET search_path TO .*;$/, CANONICAL_SEARCH_PATH)
    File.write(filename, normalized) unless normalized == sql
  end
end

ActiveSupport.on_load(:active_record) do
  require "active_record/tasks/postgresql_database_tasks"
  ActiveRecord::Tasks::PostgreSQLDatabaseTasks.prepend(DeterministicStructureSearchPath)
end
