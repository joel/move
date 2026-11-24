# frozen_string_literal: true

# The box contents grid's standalone cards (Components::Boxes::ContentsGrid),
# shared by the full render (BoxesController#show) and the unpacking streams
# that redraw the standalone region after a photo leaves the box (#889).
# Expects the including controller to set @box (MoveScopedController pattern)
# and to authorize item reads through `authorized_scope` (Action Policy).
# NB: concern modules are unchecked by Steep (Steepfile note); this module's
# surface is declared in sig/concerns.rbs like the other controller concerns.
module BoxGridItems
  extend ActiveSupport::Concern

  private

  # The grid's standalone items, newest first: the full render's membership
  # (no photo card of this box represents them) and order (the reverse of
  # Item.ordered), with their tiles preloaded.
  def standalone_grid_items
    scope = authorized_scope(@box.items)
    items = scope.where(source_media_id: nil)
                 .or(scope.where.not(source_media_id: @box.media.ready.not_generated.select(:id)))
                 .order(created_at: :desc).to_a
    preload_item_tiles(items.select(&:source_media_id))
    items
  end

  # A standalone card with a source photo reads that photo + blob for its
  # thumbnail (#416). Pass only those items: a manual item (nil source) never
  # touches the association, so preloading it would be wasted work Bullet flags.
  def preload_item_tiles(items)
    return if items.empty?

    ActiveRecord::Associations::Preloader.new(
      records: items, associations: { source_media: { image_attachment: :blob } }
    ).call
  end
end
