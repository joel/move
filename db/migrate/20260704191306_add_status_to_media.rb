# frozen_string_literal: true

# Async image ingest (#545): a Media row now exists in a `pending` state before
# its optimised blob is attached (the capture POST creates the row + enqueues
# Captures::IngestJob; the job normalizes → attaches → flips to `ready`). Every
# EXISTING media predates this and already has an attached image, so it is
# `ready`. Runs per-tenant under Apartment.
class AddStatusToMedia < ActiveRecord::Migration[8.1]
  def up
    add_column :media, :status, :string, null: false, default: "pending"
    # Backfill: all pre-existing media were created synchronously with an image.
    execute "UPDATE media SET status = 'ready'"
    add_index :media, %i[box_id status]
  end

  def down
    remove_index :media, %i[box_id status]
    remove_column :media, :status
  end
end
