# frozen_string_literal: true

# Gallery — a Move-wide browse surface for every photo, generalising the per-box
# contents grid (B1) to the whole Move. Runs inside the tenant schema, scoped to
# one Move. Thin and read-only: any member may browse, so there is no editing-role
# guard — just authorize the read, load the media, render.
class GalleriesController < MoveScopedController
  before_action { Current.nav_section = :menu }

  # One keyset page of the grid (#718). Every request stays bounded no matter
  # how many photos a Move holds; "Load more" walks the (captured_at, id)
  # cursor until every photo is reachable — the old hard CAP left photo 301+
  # unreachable.
  PAGE = 100

  SORTS = %w[recent oldest].freeze
  DEFAULT_SORT = "recent"
  VIEWS = %w[photos groups].freeze
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  # GET /moves/:move_id/gallery?view=&room_id=&sort=&cursor=&cursor_id=

  #: () -> untyped
  def index
    authorize! @move, to: :show?, with: MovePolicy

    return groups_view if view_key == "groups"

    scope = photo_scope
    rows = page_of(scope)
    last = (rows.last if rows.size == PAGE)
    remaining = last ? beyond(scope, last).count : 0

    respond_to do |format|
      format.html { render photos_view(rows, last, remaining) }
      format.turbo_stream { render turbo_stream: page_streams(rows, last, remaining) }
    end
  end

  private

  # The Groups half (#633): item families over the #629 engine. A Move that has
  # never been clustered lazily requests its first refresh here — an idempotent,
  # claim-guarded write on a GET (a deliberate, documented exception: the claim
  # protocol makes double-GETs no-ops and the TTL self-heals a stranded claim);
  # the page's stream then replaces the "organizing" state when the job lands.

  #: () -> untyped
  def groups_view
    overview = Clusters::Overview.new.call(move: @move).value!
    Clusters::RequestRefresh.new.call(move_id: @move.id) if overview.status == :organizing
    render Views::Galleries::Groups.new(move: @move, overview: overview)
  end

  #: () -> String
  def view_key
    VIEWS.include?(params[:view]) ? params[:view] : "photos"
  end

  # Scope to media in *kept* boxes (box soft-delete does not cascade to media,
  # and a discarded box's detail page 404s) and fold in the optional room filter
  # via the same subquery. selected_room resolves through the Move's own rooms so
  # an unknown/malformed room_id is a cleared filter, never a stray query.

  #: () -> untyped
  def photo_scope
    boxes = @move.boxes
    boxes = boxes.where(room: selected_room) if selected_room
    @move.media.ready.where(box_id: boxes.select(:id))
  end

  #: () -> untyped
  def selected_room
    return @selected_room if defined?(@selected_room)

    @selected_room = (@move.rooms.find_by(id: params[:room_id]) if params[:room_id].present?)
  end

  # One page in the requested order. The order is applied in SQL *before* the
  # window, so "oldest first" reaches the genuinely oldest photos first; id
  # breaks captured_at ties for a stable page.

  #: (untyped scope) -> Array[untyped]
  def page_of(scope)
    time, id = cursor
    scope = seek(scope, time, id) if time
    scope.includes(:sourced_items, box: :room, image_attachment: :blob)
         .order(captured_at: sort_direction, id: sort_direction)
         .limit(PAGE)
         .to_a
  end

  # Keyset cursor [time, id] for the next page in the active walk order. Both
  # halves come from the last row of the previous page; id disambiguates rows
  # sharing captured_at (the activity feed's #194 lesson). A malformed/partial
  # cursor yields [nil] → the first page — the same forgiveness as an unknown
  # room_id; the uuid guard keeps garbage out of the SQL ::uuid cast, which
  # would 500 instead of forgiving.

  #: () -> Array[untyped]
  def cursor
    return [nil] if params[:cursor].blank? || !params[:cursor_id].to_s.match?(UUID)

    time = Time.iso8601(params[:cursor].to_s)
    # Ruby parses year-999999 timestamps that overflow Postgres's range into a
    # PG::DatetimeFieldOverflow 500 — treat them as the malformed cursors they
    # are (real cursors are server-minted and always in range).
    return [nil] unless time.year.between?(1, 9999)

    [time, params[:cursor_id].to_s]
  rescue ArgumentError
    [nil]
  end

  #: (untyped scope, untyped time, untyped id) -> untyped
  def seek(scope, time, id)
    sort_direction == :desc ? scope.captured_before(time, id) : scope.captured_after(time, id)
  end

  # The rows beyond `media` in the active walk order — what "Load more" fetches
  # next, and the pager's remaining count (SQL COUNT, never a Ruby reduce).

  #: (untyped scope, untyped media) -> untyped
  def beyond(scope, media)
    seek(scope, media.captured_at, media.id)
  end

  #: (Array[untyped] rows, untyped last, Integer remaining) -> untyped
  def photos_view(rows, last, remaining)
    Views::Galleries::Index.new(
      move: @move, media: rows, rooms: rooms_with_photos,
      selected_room_id: selected_room&.id, sort_key: sort_key,
      cursor: last, remaining: remaining
    )
  end

  # "Load more": append the next page's tiles into the grid (inside the live
  # lightbox controller subtree — its targets are queried at open time) and
  # replace the pager with the advanced cursor. Tiles carry dom_ids, so Turbo
  # de-dupes a double-submitted page instead of appending twice.

  #: (Array[untyped] rows, untyped last, Integer remaining) -> Array[untyped]
  def page_streams(rows, last, remaining)
    [
      turbo_stream.append(
        Components::Gallery::Grid::TILES_ID,
        view_context.render(Components::Gallery::Tiles.new(move: @move, media: rows))
      ),
      turbo_stream.replace(
        Components::Gallery::Pager::ID,
        view_context.render(Components::Gallery::Pager.new(
                              move: @move, cursor: last, remaining: remaining,
                              sort_key: sort_key, selected_room_id: selected_room&.id
                            ))
      )
    ]
  end

  # Only rooms that actually own at least one photo (in a kept box) earn a filter
  # chip — a read-only surface must not offer a zero-result facet (UX rule 3). All
  # SQL: rooms whose id is among the room_ids of kept boxes that have media.

  #: () -> untyped
  def rooms_with_photos
    # ready only (#545): the grid excludes pending/failed captures, so a room
    # whose only media is still ingesting must not be offered as a facet that
    # then renders an empty grid (zero-result facet — ux-conventions.md).
    photographed_box_ids = @move.boxes.where(id: @move.media.ready.select(:box_id)).where.not(room_id: nil)
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
