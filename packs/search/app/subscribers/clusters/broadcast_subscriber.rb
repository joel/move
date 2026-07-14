# frozen_string_literal: true

module Clusters
  # Pushes the freshly-recomputed Groups grid to every gallery viewer (#633):
  # a `clusters.recomputed` event re-renders the grid server-side (inside the
  # emitter's Apartment tenant) and replaces it over the Move's
  # :gallery_groups stream — the page flips from "Organizing your items…" (or
  # a stale grid) to the new families without a reload or a poll. The payload
  # is read-only (no mutating affordances), so one broadcast is safe for every
  # viewer regardless of role.
  class BroadcastSubscriber
    def emit(event)
      return unless event[:name] == "clusters.recomputed"

      move = Move.find_by(id: event[:payload]&.dig(:move_id))
      broadcast(move) if move
    end

    private

    # A broadcast must never break its emitter (AGENTS.md §1 #4): this runs
    # synchronously inside Clusters::Recompute (request, job or rake). Worst
    # case of a failure is a missed live update — the next recompute or a
    # reload re-renders the grid.
    def broadcast(move)
      Turbo::StreamsChannel.broadcast_replace_to(
        move, :gallery_groups,
        target: Components::Gallery::GroupsGrid::ID,
        html: ApplicationController.render(Components::Gallery::GroupsGrid.new(move: move), layout: false)
      )
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 broadcast must not break emitter
      Rails.logger.warn("[clusters] groups grid broadcast failed: #{e.class}: #{e.message}")
    end
  end
end
