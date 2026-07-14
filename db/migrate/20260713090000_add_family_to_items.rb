# frozen_string_literal: true

# Hidden classification facet (#626, PR 1 of #625): a short generic phrase the
# recognition model assigns per detection ("batteries & power"). Never rendered
# in any UI — its only consumers are the search projection text (embedded +
# FTS-searchable) and the cluster engine. Nullable on purpose: manual/MCP items
# and everything created before this migration simply have none (no backfill —
# they participate in search/clustering by name alone). Deliberately NOT added
# to the Logidze whitelist ({name}): machine-written metadata, not user history.
class AddFamilyToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :family, :string
  end
end
