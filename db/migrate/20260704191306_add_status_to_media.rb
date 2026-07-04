# frozen_string_literal: true

# Async image ingest (#545): a Media row can now exist in a `pending` state
# before its optimised blob is attached (the async web capture creates the row +
# enqueues Captures::IngestJob; the job normalizes → attaches → flips to `ready`).
#
# The DEFAULT is `ready`, not `pending`: only the async path creates a row before
# its image, and it sets `pending` explicitly. Every synchronous creator (MCP
# Captures::Create, AI-generated images, demo/seed sample builders) attaches
# in-request, so defaulting to `ready` means a creator that omits `status` can't
# accidentally strand a completed photo as forever-"pending". Existing rows all
# have images, so the default backfills them to `ready` for free. Runs per-tenant
# under Apartment.
class AddStatusToMedia < ActiveRecord::Migration[8.1]
  def up
    add_column :media, :status, :string, null: false, default: "ready"
    add_index :media, %i[box_id status]
  end

  def down
    remove_index :media, %i[box_id status]
    remove_column :media, :status
  end
end
