# frozen_string_literal: true

# The gallery's keyset pagination (#718) orders by (captured_at, id) across a
# whole move; without a matching index every Load more top-N-sorts the move's
# media before LIMIT, and the pager's remaining COUNT repeats the work —
# degrading precisely on the large moves pagination exists for (PR #719
# review). move_id (not box_id) leads so the equality prefix leaves the walk
# order streamable in one ordered scan — the kept-box subquery stays a residual
# filter, which a box_id-led index cannot avoid because the ORDER BY is not
# box-prefixed. Partial on kept rows to mirror Media's default_scope.
class AddGalleryKeysetIndexToMedia < ActiveRecord::Migration[8.1]
  def change
    add_index :media, %i[move_id status captured_at id],
              where: "discarded_at IS NULL",
              name: "index_media_gallery_keyset"
  end
end
