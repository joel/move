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
      review_suggestion: review_suggestion, **vocabulary
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
      redirect_after_update(item)
    in Dry::Monads::Failure(Symbol => reason)
      redirect_to move_item_path(@move, @item), alert: vocabulary_error(reason)
    in Dry::Monads::Failure(errors)
      @item.assign_attributes(item_attributes)
      @item.errors.merge!(errors) if errors.respond_to?(:each)
      render Views::Items::Show.new(
        move: @move, item: @item, boxes: @move.boxes.includes(:room).ordered,
        review_suggestion: review_suggestion, **vocabulary
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

  # An edit reached via review "Correct" carries review_suggestion_id; saving
  # resolves *that* suggestion (works for conflicts too, whose linked item is the
  # one being edited) and resumes the review at the next unresolved suggestion in
  # its box (or the queue when none remain).
  #
  # Guard: only honour the review context when the carried suggestion actually
  # belongs to the saved item. "Correct" only ever navigates to suggestion.item
  # (see RecognitionSuggestionsController#correct), so a mismatch means a stale or
  # crafted form trying to resolve an unrelated suggestion — fall back to a plain
  # item-edit redirect and resolve nothing.
  def redirect_after_update(item)
    suggestion = review_suggestion
    return redirect_to(move_item_path(@move, item), notice: t(".updated", name: item.name)) unless suggestion && suggestion.item_id == item.id

    # Saving the edit is what resolves the suggestion (Correct only navigates here)
    # — so an abandoned correction leaves it pending in the queue.
    RecognitionSuggestions::Correct.new.call(suggestion:, actor: current_user) if suggestion.unresolved?
    box = suggestion.box
    nxt = box.recognition_suggestions.unresolved.by_confidence.first
    target = nxt ? move_box_review_path(@move, box, nxt) : move_box_review_index_path(@move, box)
    redirect_to target, notice: t(".updated", name: item.name)
  end

  # The specific suggestion being reviewed (carried through the edit), scoped to
  # the tenant's Move. nil for an ordinary item edit (no review context).
  def review_suggestion
    id = params[:review_suggestion_id].presence
    id && @move.recognition_suggestions.find_by(id:)
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

  def require_writable_move!
    authorize_move_mutation!
    return if @move.writable?

    redirect_to move_boxes_path(@move), alert: t("items.archived")
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
