# frozen_string_literal: true

# Join row between an Item and a managed Tag (D5). No payload of its own; the
# unique [item_id, tag_id] index keeps an item from carrying the same tag twice.
class ItemTag < ApplicationRecord
  belongs_to :item
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :item_id }

  # Tag names feed an item's search_text, and a tag-only edit changes item_tags
  # without touching the items row — so Item#after_commit won't fire. Refresh the
  # item's search projection when its tag links change (D8).
  after_commit :reindex_item, on: %i[create destroy]

  private

  def reindex_item
    Search::RefreshDocumentJob.perform_later(item_id, tenant: Apartment::Tenant.current)
  end
end
