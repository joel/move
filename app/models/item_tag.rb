# frozen_string_literal: true

# Join row between an Item and a managed Tag (D5). No payload of its own; the
# unique [item_id, tag_id] index keeps an item from carrying the same tag twice.
class ItemTag < ApplicationRecord
  belongs_to :item
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :item_id }
end
