# frozen_string_literal: true

# D1 — Hybrid search over a Move's items (Domain §7). Runs inside the tenant
# schema, scoped to one Move. Thin: read the query, call Search::Items, render.
# Read-only — any member of the Move may search; results enforce the §7.4
# exclusions in the action.
class SearchesController < MoveScopedController
  before_action { Current.nav_section = :search }

  # GET /moves/:move_id/search?q=...
  def index
    query = params[:q].to_s
    results = query.present? ? Search::Items.new.call(move: @move, query: query).value! : []

    render Views::Searches::Index.new(move: @move, query: query, results: results)
  end
end
