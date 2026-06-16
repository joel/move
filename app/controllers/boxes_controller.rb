# frozen_string_literal: true

# A2 — Boxes Home (index/new/create) and B1 — Box Detail & lifecycle
# (show/edit/update/transition). Runs inside an Organization tenant schema (the
# subdomain elevator switches Apartment first) and is scoped to one Move. Thin:
# authorize, call the action, pattern-match, render.
class BoxesController < MoveScopedController
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
      selected_room_id: selected_room&.id,
      item_counts: @move.items.in_box.group(:box_id).count,
      editable: editable_move?
    )
  end

  # GET /moves/:move_id/boxes/:id
  def show
    items = authorized_scope(@box.items).in_box
    render Views::Boxes::Show.new(
      move: @move, box: @box, items: items.ordered,
      # Preload the blob only (proxy URLs use the original; no variants/preview).
      media: @box.media.includes(image_attachment: :blob).recent_first,
      editable: editable_move?, pending_count: reviewable_count(items),
      # Photos that produced an item (in-box OR removed) — the per-photo review
      # walk's membership; only these gallery photos link into review.
      reviewable_media_ids: @box.items.where.not(source_media_id: nil).distinct.pluck(:source_media_id),
      # Orphaned photos worth a recovery affordance (failed / zero-detection) —
      # these link to the recovery screen instead of being dead-end thumbnails.
      recoverable_media_ids: recoverable_media_ids
    )
  end

  # GET /moves/:move_id/boxes/new
  def new
    render Views::Boxes::New.new(
      move: @move, box: @move.boxes.new, rooms: @move.rooms.order(:name),
      dimension_presets: @move.boxes.dimension_presets
    )
  end

  # GET /moves/:move_id/boxes/:id/edit
  def edit
    render Views::Boxes::Edit.new(
      move: @move, box: @box, rooms: @move.rooms.order(:name),
      # Exclude the box being edited from its own suggestions.
      dimension_presets: @move.boxes.where.not(id: @box.id).dimension_presets
    )
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
      render Views::Boxes::New.new(move: @move, box: box, rooms: @move.rooms.order(:name),
                                   dimension_presets: @move.boxes.dimension_presets),
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
      render Views::Boxes::Edit.new(move: @move, box: @box, rooms: @move.rooms.order(:name),
                                    dimension_presets: @move.boxes.where.not(id: @box.id).dimension_presets),
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

  # Items the C2 review walk can act on: unreviewed (pending_review or
  # needs_correction) AND backed by a photo *in this box*. The walk (review_media)
  # only spans @box.media, so an item moved in from another box keeps its foreign
  # source_media_id and isn't reviewable here — require the source photo to belong
  # to @box, not just be present. A photo-less correction is resolved on C3. Drives
  # the box review badge, keeping it from advertising a dead-end CTA (#146).
  def reviewable_count(items)
    items.where(review_state: %w[pending_review needs_correction])
         .where(source_media_id: @box.media.select(:id)).count
  end

  # Orphaned photos whose latest recognition attempt is settled: a terminal run
  # (failed / true zero-detection), none in flight, and nothing to act on. Three
  # exclusions, all mirrored by RecoveriesController#orphaned?/#recovered?:
  #  - MOVE-wide item check (not box-scoped): Items::Move keeps source_media_id, so
  #    a box-scoped check would re-flag a photo once its item moves to another box.
  #    `with_discarded`: a soft-deleted item still counts, so deleting it doesn't
  #    re-surface a recovery tile that could re-source a duplicate (#198).
  #  - has a suggestion → recognition produced a result. A conflict-only run records
  #    suggestions but creates no item (no-overwrite); offering manual add there
  #    would recreate the very duplicate the conflict path avoids.
  #  - still queued/processing → transient, stays a plain thumbnail (#162).
  # The per-record equivalent is Media#orphaned? (used by the recovery flow); this
  # is the set-based form for the gallery, with the in-flight/terminal filter added.
  def recoverable_media_ids
    item_media = @move.items.with_discarded.where.not(source_media_id: nil).select(:source_media_id)
    suggestion_media = RecognitionSuggestion.where(box: @box).select(:media_id)
    runs = RecognitionRun.where(box: @box)
    @box.media
        .where.not(id: item_media)
        .where.not(id: suggestion_media)
        .where(id: runs.where(status: RecognitionRun::TERMINAL).select(:media_id))
        .where.not(id: runs.where(status: %w[queued processing]).select(:media_id))
        .pluck(:id)
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

  # Archived Moves are read-only — no creating, editing or transitioning boxes.
  # Explicit key (not lazy) since this runs across several actions.

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
      pending_review: @move.items.pending_review.count
    }
  end

  def box_params
    params.expect(box: %i[number room_name length_cm width_cm height_cm weight_kg])
  end
end
