# frozen_string_literal: true

# A durable, atomic in-progress claim for item-image generation (#416). Before
# the (paid) vendor call, GenerateImage claims the item by stamping
# image_generating_at; a concurrent submit (double-click / two tabs / retry) fails
# the claim and never reaches the provider — so one user action bills at most one
# image. The claim is reclaimable after a staleness window so a crashed job can't
# wedge the item. Not user content → kept out of the items Logidze whitelist.
class AddImageGeneratingAtToItems < ActiveRecord::Migration[8.1]
  def change
    add_column :items, :image_generating_at, :datetime
  end
end
