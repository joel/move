# frozen_string_literal: true

# One item family in full (#633) — the gallery Groups drill-down. Read-only like
# the gallery itself: any member may browse, so there is no editing-role guard.
# A recompute can retire a cluster id between a card render and the tap; that
# lands here as a friendly redirect back to the (fresh) Groups view.
class GalleryGroupsController < MoveScopedController
  before_action { Current.nav_section = :menu }

  # GET /moves/:move_id/gallery/groups/:id

  #: () -> untyped
  def show
    authorize! @move, to: :show?, with: MovePolicy

    case Clusters::Members.new.call(move: @move, cluster_id: params[:id])
    in Dry::Monads::Success(result)
      render Views::GalleryGroups::Show.new(move: @move, cluster: result.cluster, members: result.items)
    in Dry::Monads::Failure(:not_found)
      redirect_to move_gallery_path(@move, view: "groups"), alert: t(".gone")
    end
  end
end
