# frozen_string_literal: true

# Soft-delete foundation (Technical Foundation §9, Domain §11). User-authored
# domain records are discarded, not destroyed. Beyond `discarded_at`, Move needs a
# *cascade trace* so a parent restore brings back only the children discarded by
# the same delete action (never resurrecting a child discarded earlier for its own
# reasons): each delete action stamps one `discard_batch_id`, and children also
# record which parent discarded them. All ids are uuid to match the app's PKs.
class AddDiscardColumnsToUserAuthoredModels < ActiveRecord::Migration[8.1]
  TABLES = %i[moves boxes items rooms categories tags media].freeze

  def change
    TABLES.each do |table|
      add_column table, :discarded_at, :datetime
      add_column table, :discard_batch_id, :uuid
      add_column table, :discarded_by_parent_type, :string
      add_column table, :discarded_by_parent_id, :uuid

      add_index table, :discarded_at
      add_index table, :discard_batch_id
    end
  end
end
