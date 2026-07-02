# frozen_string_literal: true

# A1 — Create / select Move. Runs inside an Organization tenant schema (the
# subdomain elevator switches Apartment before this controller is reached).
# Tenant-scoped but not Move-scoped (the collection has no :move_id), so it
# extends TenantController, not MoveScopedController (keeps the default layout).
class MovesController < TenantController
  # GET /moves
  def index
    @moves = authorized_scope(Move.all).order(created_at: :desc)

    case Moves::CardMetrics.new.call(move_ids: @moves.map(&:id))
    in Dry::Monads::Success(metrics)
      render Views::Moves::Index.new(
        moves: @moves, organization: current_organization, user: current_user, metrics: metrics
      )
    end
  end

  # GET /moves/new
  def new
    @move = Move.new(unit_system: "metric")
    render Views::Moves::New.new(move: @move)
  end

  # POST /moves
  def create
    authorize! Move, to: :create?, with: MovePolicy
    result = Moves::Create.new.call(params: move_params.to_h.symbolize_keys, creator: current_user)

    case result
    in Dry::Monads::Success(move)
      redirect_to moves_path, notice: t(".created", name: move.name)
    in Dry::Monads::Failure(errors)
      @move = Move.new(move_params)
      @move.errors.merge!(errors) if errors.respond_to?(:each)
      render Views::Moves::New.new(move: @move), status: :unprocessable_content
    end
  end

  # DELETE /moves/:id — currently only the onboarding sample Move is removable from
  # the UI (the card surfaces the affordance only when sample?); the action itself
  # is general. Authorize through the same scope the index uses so a non-member or
  # non-admin can't target another Move.
  def destroy
    move = authorized_scope(Move.all).find(params.expect(:id))
    authorize! move, to: :destroy?, with: MovePolicy
    result = Moves::Destroy.new.call(move: move)

    case result
    in Dry::Monads::Success(_)
      redirect_to moves_path, notice: t(".destroyed", name: move.name)
    in Dry::Monads::Failure(:not_sample)
      # Only the onboarding sample is removable today; a request for any other Move
      # is a crafted/stale one the UI never offers.
      head :forbidden
    in Dry::Monads::Failure(_)
      redirect_to moves_path, alert: t(".destroy_failed")
    end
  end

  private

  def move_params
    params.expect(
      move: %i[name planned_on origin_address destination_address unit_system]
    )
  end
end
