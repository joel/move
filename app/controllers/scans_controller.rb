# frozen_string_literal: true

# E2 — QR scan. `show` is the live camera + manual-entry scanner page; `resolve`
# looks a scanned token up (tenant-wide, via Qr::Resolve) and renders one of the
# E2 states. Resolution is read-only and never changes box status; an unknown or
# foreign token yields the non-disclosing "unrecognized" state. Both render in
# the Move app shell.
class ScansController < MoveScopedController
  before_action { Current.nav_section = :scan }

  # GET /moves/:move_id/scan
  def show
    authorize! @move, to: :show?, with: MovePolicy
    render Views::Scans::Show.new(move: @move)
  end

  # GET /moves/:move_id/scan/:token
  def resolve
    authorize! @move, to: :show?, with: MovePolicy

    case Qr::Resolve.new.call(move: @move, token: params[:token], actor: current_user)
    in Dry::Monads::Success(box) if box.move.writable?
      render Views::Scans::Resolved.new(move: @move, box: box)
    in Dry::Monads::Success(box)
      render Views::Scans::Archived.new(move: @move, box: box)
    in Dry::Monads::Failure(:unrecognized)
      render Views::Scans::Unrecognized.new(move: @move), status: :not_found
    end
  end
end
