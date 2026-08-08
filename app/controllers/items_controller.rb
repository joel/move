# frozen_string_literal: true

# B3 — Manual add item (new/create, scoped to a Box) and C3 — Item detail / edit
# (show/update + move/mark_removed/restore, scoped to the Move so the record
# survives a box-to-box move). Runs inside an Organization tenant schema. Thin:
# authorize, call the action, pattern-match, render.
class ItemsController < MoveScopedController
  before_action :set_box, only: %i[new create]
  before_action :set_item, only: %i[show update destroy move mark_removed restore generate_image]
  before_action :require_writable_move!,
                only: %i[new create update destroy move mark_removed restore generate_image]

  # GET /moves/:move_id/items/:id

  #: () -> untyped
  def show
    render Views::Items::Show.new(
      move: @move, item: @item, boxes: @move.boxes.includes(:room).ordered,
      editable: editable_move?, photo_siblings: photo_siblings(@item),
      find_list_pinned: find_list_pinned?
    )
  end

  # GET /moves/:move_id/boxes/:box_id/items/new

  #: () -> untyped
  def new
    return redirect_to move_box_path(@move, @box), alert: t("items.create.box_closed") if pure_add_closed?

    item = @box.items.new(move: @move)
    authorize! item, to: :create?, with: ItemPolicy
    render Views::Items::New.new(
      move: @move, box: @box, item: item, source_media_id: source_media_id
    )
  end

  # POST /moves/:move_id/boxes/:box_id/items

  #: () -> untyped
  def create
    authorize! @box.items.new(move: @move), to: :create?, with: ItemPolicy
    media = source_media
    result = Items::CreateManual.new.call(
      box: @box, params: item_params, creator: current_user, source_media: media,
      # A pure new-item add is packing-only. Gate on the *validated* source photo
      # (a settled orphan), not the raw param: a forged/stale source_media_id that
      # doesn't resolve is a pure add, not a recovery, so it must still be gated.
      require_open: media.nil?
    )

    case result
    in Dry::Monads::Success(item)
      redirect_to move_box_path(@move, @box), notice: t(".created", name: item.name)
    in Dry::Monads::Failure(:not_capturable)
      redirect_to move_box_path(@move, @box), alert: t(".box_closed")
    in Dry::Monads::Failure(errors)
      item = @box.items.new(item_attributes.merge(move: @move))
      item.errors.merge!(errors) if errors.respond_to?(:each)
      render Views::Items::New.new(
        move: @move, box: @box, item: item, source_media_id: source_media_id
      ), status: :unprocessable_content
    end
  end

  # PATCH /moves/:move_id/items/:id
  # C3 auto-saves: the editable form submits on every field change as a Turbo
  # Stream and only the inline "Saved ✓" badge is swapped (the form fields keep
  # their DOM state). The HTML branches remain for non-Turbo clients / B-flows.

  #: () -> untyped
  def update
    result = Items::Update.new.call(item: @item, params: item_params, editor: current_user)

    case result
    in Dry::Monads::Success(item)
      respond_to do |format|
        # Refresh the state chip too: the edit promotes the item to `confirmed`,
        # so the overlaid "Auto-confirmed"/"Pending review" badge must follow live.
        format.turbo_stream do
          render turbo_stream: [save_status_stream(:saved), state_badge_stream(item)]
        end
        format.html { redirect_to move_item_path(@move, item), notice: t(".updated", name: item.name) }
      end
    in Dry::Monads::Failure(Symbol)
      message = t("items.form.failed")
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
        # form (not the read-only view) to show the validation errors. Pin state
        # rides along exactly as in #show — omitting it flipped a pinned item's
        # toggle back to "Add to find list" (Codex #733).
        format.html do
          render Views::Items::Show.new(
            move: @move, item: @item, boxes: @move.boxes.includes(:room).ordered,
            editable: true, photo_siblings: photo_siblings(@item),
            find_list_pinned: find_list_pinned?
          ), status: :unprocessable_content
        end
      end
    end
  end

  # DELETE /moves/:move_id/items/:id
  # Packing-phase delete (C3 shows this while the box is still packing): the item
  # was added by mistake. Soft-deletes the item and its now-orphaned source photo;
  # the activity feed offers a restore. Distinct from mark_removed (unpacking).

  #: () -> untyped
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

  #: () -> untyped
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
  # The C3 "mark unpacked" path. Items::MarkRemoved enforces the unpacking-phase
  # rule (delete is the tool while packing), so a stale form / direct PATCH on a
  # still-packing item is refused with a friendly alert.

  #: () -> untyped
  def mark_removed
    case Items::MarkRemoved.new.call(item: @item, actor: current_user)
    in Dry::Monads::Success(_)
      removed_response
    in Dry::Monads::Failure(:wrong_phase)
      respond_with_streams([], redirect: item_path, toast: true, status: :unprocessable_content) do
        [:alert, t(".wrong_phase")]
      end
    in Dry::Monads::Failure(_)
      respond_with_streams([], redirect: item_path, toast: true, status: :unprocessable_content) do
        [:alert, t(".failed")]
      end
    end
  end

  # PATCH /moves/:move_id/items/:id/restore

  #: () -> untyped
  def restore
    Items::RestoreToBox.new.call(item: @item, actor: current_user)
    respond_with_streams(presence_streams, redirect: item_path, toast: true) { [:notice, t(".restored")] }
  end

  # POST /moves/:move_id/items/:id/generate_image (#416)
  # Claims the item (atomic) and enqueues the slow vendor call off the request
  # path, then swaps the box-contents card to its current state; the job's
  # broadcast completes it (→ image, or a retryable failed state). Defends the
  # hidden affordance: only a source-less item on an image-ready Move qualifies.

  #: () -> untyped
  def generate_image
    return head :unprocessable_content unless @item.source_media_id.nil? && @move.image_generation_ready?

    # Claim synchronously BEFORE enqueue, so the in-flight state is observable when
    # the response renders and only the winner of a concurrent submit enqueues the
    # (paid) job. A loser just re-renders the card, which already reflects the claim.
    if (claimed_at = @item.claim_image_generation!)
      # Pass the claim token: the job verifies the item still holds THIS claim
      # before spending, so a stale-reclaimed duplicate job can't double-spend.
      Items::GenerateImageJob.perform_later(
        @item.id, tenant: Apartment::Tenant.current, actor_id: current_user&.id, claimed_at: claimed_at.to_i
      )
    end

    respond_with_streams(item_card_stream, redirect: move_box_path(@move, @item.box))
  end

  private

  # Render the card in whatever state it is NOW (reload): claimed → generating; an
  # inline/very-fast job that already attached → image; an inline failure that
  # released the claim → the retryable placeholder. ItemCard derives generating
  # from the persisted claim, so the response never overwrites a completed/failed
  # card with a stale spinner (#416 Codex).

  #: () -> Array[untyped]
  def item_card_stream
    @item.reload
    [turbo_stream.replace(
      Components::Boxes::ItemCard.dom_id(@item),
      view_context.render(Components::Boxes::ItemCard.new(item: @item, move: @move, image_ready: true))
    )]
  end

  # Turbo Stream that swaps the inline auto-save badge in the C3 header.

  #: (Symbol state, ?message: String?) -> untyped
  def save_status_stream(state, message: nil)
    turbo_stream.replace(
      Components::Ui::SaveStatus::ID,
      view_context.render(Components::Ui::SaveStatus.new(state: state, message: message))
    )
  end

  # Turbo Stream that refreshes the item's review-state chip after a save (the
  # edit promotes it to `confirmed`, so the overlaid badge must update in place).

  #: (untyped item) -> untyped
  def state_badge_stream(item)
    turbo_stream.replace(
      Components::ItemStateBadge.dom_id(item),
      view_context.render(Components::ItemStateBadge.new(item: item))
    )
  end

  #: () -> String
  def item_path
    move_item_path(@move, @item)
  end

  # The mark_removed success response (#755): removing the box's last item
  # auto-completes it. The item page stays put either way (presence streams);
  # the completion is off-screen, so it surfaces with a LINKING toast (UX rule
  # 1 — the find-list box_opened pattern), replacing the plain removed toast,
  # never stacking two. flash.now scopes the link to the stream render; the
  # no-JS fallback REDIRECTS, so there it rides the persistent flash.

  #: () -> untyped
  def removed_response
    completed = Boxes::CompleteIfEmpty.new.call(box: @item.box, actor: current_user)
    if completed in Dry::Monads::Success(Box => box)
      link_flash = request.format.turbo_stream? ? flash.now : flash
      link_flash[:action_href] = move_box_path(@move, box)
      link_flash[:action_label] = t(".view_box")
      respond_with_streams(presence_streams, redirect: item_path, toast: true) do
        [:notice, t(".box_unpacked", number: box.number)]
      end
    else
      respond_with_streams(presence_streams, redirect: item_path, toast: true) { [:notice, t(".removed")] }
    end
  end

  # Streams for a presence flip (mark_removed / restore): the overlay badges (the
  # "Removed" chip appears/disappears) and the footer controls (Move hides while
  # removed; the presence button swaps Restore↔Mark-unpacked/Delete). No reload.

  #: () -> Array[untyped]
  def presence_streams
    @item.reload
    [
      turbo_stream.replace(Components::Items::StateBadges::ID,
                           view_context.render(Components::Items::StateBadges.new(item: @item))),
      turbo_stream.replace(Components::Items::PresenceControls::ID,
                           view_context.render(Components::Items::PresenceControls.new(
                                                 move: @move, item: @item, boxes: presence_boxes,
                                                 editable: editable_move?
                                               ))),
      # A presence flip changes the item's own searchability, so the "same
      # group" rail must follow (#642/#643): unpacking hides it, restoring
      # brings it back — the rail self-loads the live siblings on re-render.
      turbo_stream.replace(Components::Items::GroupRail::ID,
                           view_context.render(Components::Items::GroupRail.new(move: @move, item: @item)))
    ]
  end

  # The Move control renders only the *other* boxes (the current one is excluded),
  # and only while the item is in-box. Query the targets directly so a single-box
  # Move (or a removed item) loads nothing — no eager-loaded :room left unused.

  #: () -> untyped
  def presence_boxes
    return [] if @item.removed?

    @move.boxes.where.not(id: @item.box_id).includes(:room).ordered
  end

  # How many *other* in-box items were detected in the same photo — drives the C3
  # "detected with N other items in this photo" line so a single image reads as
  # many items, not one. Zero for manually-added items (no source media).

  #: (untyped item) -> Integer
  def photo_siblings(item)
    return 0 unless item.created_via == "recognition" && item.source_media_id

    @move.items.in_box.where(source_media_id: item.source_media_id).where.not(id: item.id).count
  end

  # Whether the caller pinned this item onto their find list (#730) — shared by
  # the show render and update's validation re-render.

  #: () -> bool
  def find_list_pinned?
    FindListEntry.exists?(move_id: @move.id, user_id: current_user.id, item_id: @item.id)
  end

  #: () -> untyped
  def set_box
    @box = authorized_scope(@move.boxes).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # A pure manual add (no *valid* source photo) targeting a box that isn't open
  # (packing). A recovery add resolves to a settled orphan photo (corrects a
  # captured photo) and stays allowed in any phase; a forged/stale id that doesn't
  # resolve is treated as a pure add. Mirrors Items::CreateManual#ensure_open.

  #: () -> bool
  def pure_add_closed?
    source_media.nil? && !@box.capturable?
  end

  # Recovery flow: a manual add launched from an orphaned photo carries the photo
  # id (query param on `new`, hidden field on `create`) so the item attaches to it.

  #: () -> untyped
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

  #: () -> untyped
  def source_media
    return @source_media if defined?(@source_media)

    @source_media =
      if source_media_id
        media = @box.media.find_by(id: source_media_id)
        media if media&.orphaned? && !media.recognition_in_flight?
      end
  end

  #: () -> untyped
  def set_item
    @item = authorized_scope(@move.items).find(params.expect(:id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  #: (untyped reason) -> String
  def move_error(reason)
    case reason
    when :removed then t("items.move.removed_item")
    when :same_box then t("items.move.same_box")
    when :cross_move, :box_missing then t("items.move.invalid")
    else t("items.move.failed")
    end
  end

  #: () -> Hash[Symbol, untyped]
  def item_params
    item_attributes.to_h.symbolize_keys
  end

  #: () -> untyped
  def item_attributes
    params.expect(item: [:name])
  end
end
