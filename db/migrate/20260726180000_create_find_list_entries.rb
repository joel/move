# frozen_string_literal: true

# Personal "find list" (#730): a user's pinned items within one Move — the
# working set behind the box-grouped picking list. One row per (move, user,
# item); rows die with their item (ON DELETE CASCADE, the
# item_search_documents precedent) so Moves::Destroy needs no DELETE_ORDER
# entry for this table.
class CreateFindListEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :find_list_entries, id: :uuid, if_not_exists: true do |t|
      # Same-schema FK: find_list_entries and moves are cloned together per tenant.
      t.references :move, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      # References public.users; no cross-schema FK (move_memberships precedent).
      t.uuid :user_id, null: false
      t.references :item, null: false, type: :uuid, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
    add_index :find_list_entries, %i[move_id user_id item_id], unique: true
    add_index :find_list_entries, :user_id
  end
end
