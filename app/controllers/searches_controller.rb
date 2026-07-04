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
      # Remember the query only when it actually found something, so the empty
      # state surfaces useful re-runs rather than dead ends (#338, ux principle 4).
      recent_searches = recent.record(query) if results.any?
    end

    render Views::Searches::Index.new(
      move: @move, query: query, results: results, recent_searches: recent_searches
    )
  end
end
