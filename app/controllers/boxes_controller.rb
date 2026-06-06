# frozen_string_literal: true

# A2 — Boxes Home (index/new/create) and B1 — Box Detail & lifecycle
# (show/edit/update/transition). Runs inside an Organization tenant schema (the
# subdomain elevator switches Apartment first) and is scoped to one Move. Thin:
# authorize, call the action, pattern-match, render.
class BoxesController < ApplicationController
  layout -> { Views::Layouts::AppShellLayout }

  before_action :require_authenticated_user!
  before_action :require_tenant!
  before_action :set_move
  before_action :set_box, only: %i[show edit update transition]
  before_action :require_writable_move!, only: %i[new create edit update transition]

  # GET /moves/:move_id/boxes
  def index
    # Resolve the filter through the Move's own rooms so an unknown or malformed
    # room_id is treated as a cleared filter, never a stray query.
    selected_room = @move.rooms.find_by(id: selected_room_id) if selected_room_id
    scope = authorized_scope(@move.boxes).includes(:room)
    scope = scope.where(room: selected_room) if selected_room

    render Views::Boxes::Index.new(
      move: @move,
      boxes: scope.ordered,
      rooms: @move.rooms.order(:name),
      summary: move_summary,
      selected_room_id: selected_room&.id
    )
  end

  # GET /moves/:move_id/boxes/:id
  def show
    render Views::Boxes::Show.new(move: @move, box: @box)
  end

  # GET /moves/:move_id/boxes/new
  def new
    render Views::Boxes::New.new(
      move: @move, box: @move.boxes.new, rooms: @move.rooms.order(:name)
    )
  end

  # GET /moves/:move_id/boxes/:id/edit
  def edit
    render Views::Boxes::Edit.new(move: @move, box: @box, rooms: @move.rooms.order(:name))
  end

  # POST /moves/:move_id/boxes
  def create
    result = Boxes::Create.new.call(
      move: @move, params: box_params.to_h.symbolize_keys, creator: current_user
    )

    case result
    in Dry::Monads::Success(box)
      redirect_to move_boxes_path(@move), notice: t(".created", number: box.number)
    in Dry::Monads::Failure(errors)
      box = @move.boxes.new(box_params)
      box.errors.merge!(errors) if errors.respond_to?(:each)
      render Views::Boxes::New.new(move: @move, box: box, rooms: @move.rooms.order(:name)),
             status: :unprocessable_content
    end
  end

  # PATCH /moves/:move_id/boxes/:id
  def update
    result = Boxes::Update.new.call(
      box: @box, params: box_params.to_h.symbolize_keys, editor: current_user
    )

    case result
    in Dry::Monads::Success(box)
      redirect_to move_box_path(@move, box), notice: t(".updated", number: box.number)
    in Dry::Monads::Failure(errors)
      @box.assign_attributes(box_params)
      @box.errors.merge!(errors) if errors.respond_to?(:each)
      render Views::Boxes::Edit.new(move: @move, box: @box, rooms: @move.rooms.order(:name)),
             status: :unprocessable_content
    end
  end

  # PATCH /moves/:move_id/boxes/:id/transition
  def transition
    result = Boxes::TransitionStatus.new.call(box: @box, to: params[:to], actor: current_user)

    case result
    in Dry::Monads::Success(box)
      redirect_to move_box_path(@move, box),
                  notice: t(".transitioned", status: t("boxes.status.#{box.status}"))
    in Dry::Monads::Failure(reason)
      redirect_to move_box_path(@move, @box), alert: transition_error(reason)
    end
  end

  private

  def set_move
    @move = authorized_scope(Move.all).find(params.expect(:move_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def transition_error(reason)
    case reason
    when :room_required then t("boxes.transition.room_required")
    when :invalid_transition then t("boxes.transition.invalid")
    else t("boxes.transition.failed")
    end
  end

  # Tenancy is non-disclosing: a Move surface only exists on an org subdomain.
  def require_tenant!
    head :not_found unless current_tenant
  end

  # Archived Moves are read-only — no creating, editing or transitioning boxes.
  # Explicit key (not lazy) since this runs across several actions.
  def require_writable_move!
    return if @move.writable?

    redirect_to move_boxes_path(@move), alert: t("boxes.archived")
  end

  def selected_room_id
    params[:room_id].presence
  end

  # Move-wide progress, independent of any room filter. Item / pending-review
  # aggregates land with Items in D5; they read as zero here.
  def move_summary
    boxes = @move.boxes
    {
      total: boxes.count,
      sealed: boxes.where.not(status: "packing").count,
      missing_dimensions: boxes.where(
        "length_cm IS NULL OR width_cm IS NULL OR height_cm IS NULL"
      ).count,
      pending_review: 0
    }
  end

  def box_params
    params.expect(box: %i[number room_name length_cm width_cm height_cm weight_kg])
  end
end
