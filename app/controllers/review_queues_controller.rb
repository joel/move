# frozen_string_literal: true

# Move-wide review queue (#654) — the C1 concept reborn at Move level: every
# photo that still holds an unreviewed co-located item, oldest capture first,
# with a "Review all" walk that crosses box boundaries (the C2 photo screen in
# queue mode). Runs inside the tenant schema, scoped to one Move. Thin and
# read-only: any member may browse — the walk's own mutations carry the guards.
class ReviewQueuesController < MoveScopedController
  before_action { Current.nav_section = :menu }

  # Same safety valve as the Gallery: bound the grid for a pathological Move.
  # FIFO means the cap keeps the OLDEST photos (the order is applied in SQL
  # before the limit), so the head of the queue is always workable.
  CAP = 300

  # GET /moves/:move_id/review

  #: () -> untyped
  def show
    authorize! @move, to: :show?, with: MovePolicy

    queue = Reviews::PendingPhotos.new.call(move: @move).value!
    rows = queue.photos.includes(box: :room, image_attachment: :blob).limit(CAP + 1).to_a
    over_cap = rows.size > CAP
    rows = rows.first(CAP)

    render Views::ReviewQueues::Show.new(
      move: @move, media: rows,
      # One grouped query, restricted to the rendered photos; the relation
      # carries the co-location join, so badge counts match what opening the
      # photo will actually confirm.
      pending_counts: queue.items.where(source_media_id: rows.map(&:id))
                           .group(:source_media_id).count,
      over_cap: over_cap,
      had_reviewable: rows.any? || reviewable_photos_exist?
    )
  end

  private

  # Splits the empty state: "all caught up" (the Move HAS review-walkable
  # photos, none pending) vs "no photos yet" (nothing ever produced an item).

  #: () -> bool
  def reviewable_photos_exist?
    @move.media.ready.not_generated
         .exists?(id: @move.items.where.not(source_media_id: nil).select(:source_media_id))
  end
end
