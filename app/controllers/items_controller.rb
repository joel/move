# frozen_string_literal: true

# B3 — Manual add item (new/create, scoped to a Box) and C3 — Item detail / edit
# (show/update + move/mark_removed/restore, scoped to the Move so the record
# survives a box-to-box move). Runs inside an Organization tenant schema. Thin:
# authorize, call the action, pattern-match, render.
class ItemsController < MoveScopedController
  before_action :set_box, only: %i[new create]
  before_action :set_item, only: %i[show update move mark_removed restore]
  before_action :require_writable_move!, only: %i[new create update move mark_removed restore]

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
    render Views::Items::New.new(move: @move, box: @box, item: item, **vocabulary)
  end

  # POST /moves/:move_id/boxes/:box_id/items
  def create
    authorize! @box.items.new(move: @move), to: :create?, with: ItemPolicy
    result = Items::CreateManual.new.call(box: @box, params: item_params, creator: current_user)

    case result
    in Dry::Monads::Success(item)
      redirect_to move_box_path(@move, @box), notice: t(".created", name: item.name)
    in Dry::Monads::Failure(Symbol => reason)
      redirect_to new_move_box_item_path(@move, @box), alert: vocabulary_error(reason)
    in Dry::Monads::Failure(errors)
      item = @box.items.new(item_attributes.merge(move: @move))
      item.errors.merge!(errors) if errors.respond_to?(:each)
      render Views::Items::New.new(move: @move, box: @box, item: item, **vocabulary),
             status: :unprocessable_content
    end
  end

  # PATCH /moves/:move_id/items/:id
  def update
    result = Items::Update.new.call(item: @item, params: item_params, editor: current_user)

    case result
    in Dry::Monads::Success(item)
      redirect_to move_item_path(@move, item), notice: t(".updated", name: item.name)
    in Dry::Monads::Failure(Symbol => reason)
      redirect_to move_item_path(@move, @item), alert: vocabulary_error(reason)
    in Dry::Monads::Failure(errors)
      @item.assign_attributes(item_attributes)
      @item.errors.merge!(errors) if errors.respond_to?(:each)
      # update is editor-gated (require_writable_move!), so re-render the editable
      # form (not the read-only view) to show the validation errors.
      render Views::Items::Show.new(
        move: @move, item: @item, boxes: @move.boxes.includes(:room).ordered,
        editable: true, photo_siblings: photo_siblings(@item), **vocabulary
      ), status: :unprocessable_content
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
  def mark_removed
    Items::MarkRemoved.new.call(item: @item, actor: current_user)
    redirect_to move_item_path(@move, @item), notice: t(".removed")
  end

  # PATCH /moves/:move_id/items/:id/restore
  def restore
    Items::RestoreToBox.new.call(item: @item, actor: current_user)
    redirect_to move_item_path(@move, @item), notice: t(".restored")
  end

  private

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
