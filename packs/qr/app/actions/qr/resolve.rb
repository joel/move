# frozen_string_literal: true

# pack_public: true -- public API of packs/qr: ScansController calls Qr::Resolve.
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Qr
  # Resolves a scanned QR token to its Box within a specific Move (E2).
  #
  # The lookup is scoped to the route's Move, not the whole tenant: a label's QR
  # encodes its own Move-scoped resolve URL, so a token that belongs to a
  # *different* Move (cross-org, or another Move in the same tenant) is simply
  # absent here and yields the same non-disclosing Failure(:unrecognized) — the
  # scanner copy is "this code isn't from your move", and we must not leak another
  # Move's box number/room/count. Resolution is read-only: it NEVER changes the
  # box's status. The archived (read-only) case is a successful resolve; the
  # caller decides how to render it from box.move.writable?.
  class Resolve < BaseAction
    def call(move:, token:, actor: nil)
      box = find(move, token)
      return Failure(:unrecognized) if box.nil?

      yield emit_event(box, actor)
      Success(box)
    end

    private

    def find(move, token)
      move.boxes.includes(:room, :move).find_by(qr_token: token.to_s.presence)
    end

    def emit_event(box, actor)
      Rails.event.notify(
        "qr.resolved", box_id: box.id, move_id: box.move_id, actor_id: actor&.id
      )
      Success()
    end
  end
end
