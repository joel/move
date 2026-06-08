# frozen_string_literal: true

module Qr
  # Resolves a scanned QR token to its Box within the current tenant (E2).
  #
  # The lookup is intentionally tenant-local: the Apartment subdomain elevator has
  # already selected the org's schema, so a token belonging to another org (or a
  # garbage code) is simply absent here and yields the same non-disclosing
  # Failure(:unrecognized) — the scanner UI must never hint that a token exists
  # elsewhere. Resolution is read-only: it NEVER changes the box's status. The
  # archived (read-only) case is a successful resolve; the caller decides how to
  # render it from box.move.writable?.
  class Resolve < BaseAction
    def call(token:, actor: nil)
      box = find(token)
      return Failure(:unrecognized) if box.nil?

      yield emit_event(box, actor)
      Success(box)
    end

    private

    def find(token)
      Box.includes(:room, :move).find_by(qr_token: token.to_s.presence)
    end

    def emit_event(box, actor)
      Rails.event.notify(
        "qr.resolved", box_id: box.id, move_id: box.move_id, actor_id: actor&.id
      )
      Success()
    end
  end
end
