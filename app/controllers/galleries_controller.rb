# frozen_string_literal: true

# Gallery — a Move-wide browse surface for every photo, generalising the per-box
# contents grid (B1) to the whole Move. Runs inside the tenant schema, scoped to
# one Move. Thin and read-only: any member may browse, so there is no editing-role
# guard — just authorize the read, load the media, render.
class GalleriesController < MoveScopedController
  before_action { Current.nav_section = :menu }

  # Safety valve for a pathological Move: cap the grid at the most-recent N photos
  # (the lightbox browses the rendered set, so we keep it bounded). Most Moves have
  # far fewer; when exceeded the view surfaces a "showing most recent N" notice.
  CAP = 300

  SORTS = %w[recent oldest].freeze
  DEFAULT_SORT = "recent"

  # GET /moves/:move_id/gallery?room_id=&sort=

  #: () -> untyped
  def index
    authorize! @move, to: :show?, with: MovePolicy

    # Scope to media in *kept* boxes (box soft-delete does not cascade to media,
    # and a discarded box's detail page 404s) and fold in the optional room filter
    # via the same subquery. selected_room resolves through the Move's own rooms so
    # an unknown/malformed room_id is a cleared filter, never a stray query.
    selected_room = @move.rooms.find_by(id: params[:room_id]) if params[:room_id].present?
    boxes = @move.boxes
    boxes = boxes.where(room: selected_room) if selected_room

    # Apply the requested order in SQL *before* the cap, so "oldest first" reaches
    # the genuinely oldest photos (the cap takes the first CAP of the chosen order,
    # not always the newest). id breaks captured_at ties for a stable page.
    rows = @move.media
                .ready # exclude captures still ingesting / failed (#545)
                .where(box_id: boxes.select(:id))
                .includes(box: :room, image_attachment: :blob)
                .order(captured_at: sort_direction, id: sort_direction)
                .limit(CAP + 1)
                .to_a
    over_cap = rows.size > CAP
    rows = rows.first(CAP)

    render Views::Galleries::Index.new(
      move: @move, media: rows, rooms: rooms_with_photos,
      selected_room_id: selected_room&.id, sort_key: sort_key, over_cap: over_cap
    )
  end

  private

  # Only rooms that actually own at least one photo (in a kept box) earn a filter
  # chip — a read-only surface must not offer a zero-result facet (UX rule 3). All
  # SQL: rooms whose id is among the room_ids of kept boxes that have media.

  #: () -> untyped
  def rooms_with_photos
    photographed_box_ids = @move.boxes.where(id: @move.media.select(:box_id)).where.not(room_id: nil)
    @move.rooms.where(id: photographed_box_ids.select(:room_id)).order(:name)
  end

  #: () -> String
  def sort_key
    SORTS.include?(params[:sort]) ? params[:sort] : DEFAULT_SORT
  end

  #: () -> Symbol
  def sort_direction
    sort_key == "oldest" ? :asc : :desc
  end
end
