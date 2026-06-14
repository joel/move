# frozen_string_literal: true

# Logidze's trigger diffs rows via `hstore(NEW.*)`, so the hstore extension must
# be available. Like citext/pg_trgm/vector, it lives once in `public` (kept on
# every tenant's search path via Apartment `persistent_schemas`); the guard stops
# Apartment's per-tenant migration pass from trying to re-create it.
class EnableHstore < ActiveRecord::Migration[8.1]
  def change
    enable_extension "hstore" unless extension_enabled?("hstore")
  end
end
