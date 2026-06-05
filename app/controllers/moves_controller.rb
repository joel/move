# frozen_string_literal: true

# A1 — Create / select Move. Runs inside an Organization tenant schema (the
# subdomain elevator switches Apartment before this controller is reached).
class MovesController < ApplicationController
  before_action :require_authenticated_user!
  before_action :require_tenant!

  # GET /moves
  def index
    @moves = authorized_scope(Move.all).order(created_at: :desc)
    render Views::Moves::Index.new(moves: @moves)
  end

  # GET /moves/new
  def new
    @move = Move.new(unit_system: "metric")
    render Views::Moves::New.new(move: @move)
  end

  # POST /moves
  def create
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

  private

  # Tenancy is non-disclosing: a Move surface only exists on an org subdomain.
  def require_tenant!
    head :not_found unless current_tenant
  end

  def move_params
    params.expect(
      move: %i[name planned_on origin_address destination_address unit_system]
    )
  end
end
