# frozen_string_literal: true

# B3 — Manual add item (new/create, scoped to a Box) and C3 — Item detail / edit
# (show/update + move/mark_removed/restore, scoped to the Move so the record
# survives a box-to-box move). Runs inside an Organization tenant schema. Thin:
# authorize, call the action, pattern-match, render.
class ItemsController < MoveScopedController
  before_action :set_box, only: %i[new create]
  before_action :set_item, only: %i[show update destroy move mark_removed restore]
  before_action :require_writable_move!, only: %i[new create update destroy move mark_removed restore]

  # GET /moves/:move_id/items/:id
  def show
    render Views::Items::Show.new(
      move: @move, item: @item, boxes: @move.boxes.includes(:room).ordered,
      editable: editable_move?, photo_siblings: photo_siblings(@item), **vocabulary
    )
  end

  # GET /moves/:move_id/boxes/:box_id/items/new
  def new
    item = @box.items.new(move: @move)
    authorize! item, to: :create?, with: ItemPolicy
    render Views::Items::New.new(
      move: @move, box: @box, item: item, source_media_id: source_media_id, **vocabulary
    )
  end

  # POST /moves/:move_id/boxes/:box_id/items
  def create
    authorize! @box.items.new(move: @move), to: :create?, with: ItemPolicy
    result = Items::CreateManual.new.call(
      box: @box, params: item_params, creator: current_user, source_media: source_media
    )

    case result
    in Dry::Monads::Success(item)
      redirect_to move_box_path(@move, @box), notice: t(".created", name: item.name)
    in Dry::Monads::Failure(Symbol => reason)
      redirect_to new_move_box_item_path(@move, @box, source_media_id: source_media_id),
                  alert: vocabulary_error(reason)
    in Dry::Monads::Failure(errors)
      item = @box.items.new(item_attributes.merge(move: @move))
      item.errors.merge!(errors) if errors.respond_to?(:each)
      render Views::Items::New.new(
        move: @move, box: @box, item: item, source_media_id: source_media_id, **vocabulary
      ), status: :unprocessable_content
    end
  end

  # PATCH /moves/:move_id/items/:id
  # C3 auto-saves: the editable form submits on every field change as a Turbo
  # Stream and only the inline "Saved ✓" badge is swapped (the form fields keep
  # their DOM state). The HTML branches remain for non-Turbo clients / B-flows.
  def update
    result = Items::Update.new.call(item: @item, params: item_params, editor: current_user)

    case result
    in Dry::Monads::Success(item)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: save_status_stream(:saved) }
        format.html { redirect_to move_item_path(@move, item), notice: t(".updated", name: item.name) }
      end
    in Dry::Monads::Failure(Symbol => reason)
      message = vocabulary_error(reason)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: save_status_stream(:error, message:), status: :unprocessable_content
        end
        format.html { redirect_to move_item_path(@move, @item), alert: message }
      end
    in Dry::Monads::Failure(errors)
      @item.assign_attributes(item_attributes)
      @item.errors.merge!(errors) if errors.respond_to?(:each)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: save_status_stream(:error, message: @item.errors.full_messages.first),
                 status: :unprocessable_content
        end
        # update is editor-gated (require_writable_move!), so re-render the editable
        # form (not the read-only view) to show the validation errors.
        format.html do
          render Views::Items::Show.new(
            move: @move, item: @item, boxes: @move.boxes.includes(:room).ordered,
            editable: true, photo_siblings: photo_siblings(@item), **vocabulary
          ), status: :unprocessable_content
        end
      end
    end
  end

  # DELETE /moves/:move_id/items/:id
  # Packing-phase delete (C3 shows this while the box is still packing): the item
  # was added by mistake. Soft-deletes the item and its now-orphaned source photo;
  # the activity feed offers a restore. Distinct from mark_removed (unpacking).
  def destroy
    result = Items::Remove.new.call(item: @item, actor: current_user)

    case result
    in Dry::Monads::Success(item)
      redirect_to move_box_path(@move, item.box), notice: t(".deleted", name: item.name)
    in Dry::Monads::Failure(:wrong_phase)
      redirect_to move_item_path(@move, @item), alert: t(".wrong_phase")
    in Dry::Monads::Failure(_)
      redirect_to move_item_path(@move, @item), alert: t(".delete_failed")
    end
  end

  # PATCH /moves/:move_id/items/:id/move
  def move
    target = @move.boxes.find_by(id: params[:target_box_id])
    result = Items::Move.new.call(item: @item, target_box: target, mover: current_user)

    case result
    in Dry::Monads::Success(item)
      redirect_to move_item_path(@move, item),
                  notice: t(".moved", number: item.box.number)
    in Dry::Monads::Failure(reason)
      redirect_to move_item_path(@move, @item), alert: move_error(reason)
    end
  end

  # PATCH /moves/:move_id/items/:id/mark_removed
  # The C3 "mark unpacked" path — valid only once the box is being unpacked.
  # While packing the right tool is delete (#destroy), so refuse here too, mirroring
  # Items::Remove's phase guard, so a stale form / direct PATCH can't mark a
  # still-packing item removed. (The C2 review walk's own remove path is separate.)
  def mark_removed
    return redirect_to move_item_path(@move, @item), alert: t(".wrong_phase") unless @item.box.unpacking? || @item.box.unpacked?

    Items::MarkRemoved.new.call(item: @item, actor: current_user)
    redirect_to move_item_path(@move, @item), notice: t(".removed")
  end

  # PATCH /moves/:move_id/items/:id/restore
  def restore
    Items::RestoreToBox.new.call(item: @item, actor: current_user)
    redirect_to move_item_path(@move, @item), notice: t(".restored")
  end

  private

  # Turbo Stream that swaps the inline auto-save badge in the C3 header.
  def save_status_stream(state, message: nil)
    turbo_stream.replace(
      Components::Ui::SaveStatus::ID,
      view_context.render(Components::Ui::SaveStatus.new(state: state, message: message))
    )
  end

  # How many *other* in-box items were detected in the same photo — drives the C3
  # "detected with N other items in this photo" line so a single image reads as
  # many items, not one. Zero for manually-added items (no source media).
  def photo_siblings(item)
    return 0 unless item.created_via == "recognition" && item.source_media_id

    @move.items.in_box.where(source_media_id: item.source_media_id).where.not(id: item.id).count
  end

  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Recovery flow: a manual add launched from an orphaned photo carries the photo
  # id (query param on `new`, hidden field on `create`) so the item attaches to it.
  def source_media_id
    params.dig(:item, :source_media_id).presence || params[:source_media_id].presence
  end

  # Bind the new item to the source photo ONLY if that photo is still a settled
  # orphan at POST time. A recovery Add-item form can go stale (the photo was
  # retried/resolved, the id is replayed for a conflict-only photo, or recognition
  # is still in flight and about to materialize items); binding then would attach a
  # duplicate to a photo that already has — or is about to have — items. Re-validate
  # here — if not, drop the binding (still create the item; the user wants it in the
  # box, just not attributed to that photo). Mirrors Media#orphaned? + the gallery's
  # settled (not-in-flight) check.
  def source_media
    return nil unless source_media_id

    media = @box.media.find_by(id: source_media_id)
    media if media&.orphaned? && !media.recognition_in_flight?
  end

  def set_item
    @item = authorized_scope(@move.items).find(params.expect(:id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # The category/tag pickers offer only the Move's managed vocabularies (D5
  # selection-only; management is D7).
  def vocabulary
    # Box-only tags are excluded from the item picker (applies-to facet).
    { categories: @move.categories.ordered, tags: @move.tags.for_items.ordered }
  end

  def move_error(reason)
    case reason
    when :removed then t("items.move.removed_item")
    when :same_box then t("items.move.same_box")
    when :cross_move, :box_missing then t("items.move.invalid")
    else t("items.move.failed")
    end
  end

  def vocabulary_error(reason)
    case reason
    when :invalid_category then t("items.form.invalid_category")
    when :invalid_tag then t("items.form.invalid_tag")
    else t("items.form.failed")
    end
  end

  def item_params
    item_attributes.to_h.symbolize_keys
  end

  def item_attributes
    params.expect(item: [:name, :category_id, :quantity, :fragile, { tag_ids: [] }])
  end
end
