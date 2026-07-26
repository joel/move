# frozen_string_literal: true

# D1 — Hybrid search over a Move's items (Domain §7). Runs inside the tenant
# schema, scoped to one Move. Thin: read the query, call Search::Items, render.
# Read-only — any member of the Move may search; results enforce the §7.4
# exclusions in the action.
class SearchesController < MoveScopedController
  before_action { Current.nav_section = :search }

  # GET /moves/:move_id/search?q=...

  #: () -> untyped
  def index
    query = params[:q].to_s
    recent = Searches::RecentSearches.new(session, @move)

    results = []
    recent_searches = recent.list
    if query.present?
      results = Search::Items.new.call(move: @move, query: query).value!
      preload_thumbnails(results)
      # Remember the query only when it actually found something, so the empty
      # state surfaces useful re-runs rather than dead ends (#338, ux principle 4).
      recent_searches = recent.record(query) if results.any?
    end

    # The caller's pins (#730): drives each result card's toggle state and the
    # header pill. One pluck per render; personal rows only. The :item join
    # (kept default scope) drops dangling pins of soft-deleted items so the
    # pill count always matches what the list renders.
    pinned_item_ids = FindListEntry.where(move_id: @move.id, user_id: current_user.id)
                                   .joins(:item).pluck(:item_id).to_set

    render Views::Searches::Index.new(
      move: @move, query: query, results: results, recent_searches: recent_searches,
      pinned_item_ids: pinned_item_ids
    )
  end

  private

  # Each result card renders its item's source photo; batch the media +
  # attachment + blob loads for the page instead of three queries per card.
  # Done here rather than in Search::Items so the pack-public action (also
  # called by the MCP tool, which never renders images) stays lean.

  #: (untyped results) -> void
  def preload_thumbnails(results)
    return if results.empty?

    # The community activerecord sig predates the kwargs Preloader API.
    ActiveRecord::Associations::Preloader.new(
      records: results.map(&:item), associations: { source_media: { image_attachment: :blob } } # steep:ignore UnexpectedKeywordArgument
    ).call # steep:ignore NoMethod
  end
end
