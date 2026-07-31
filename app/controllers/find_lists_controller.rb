# frozen_string_literal: true

# The personal find list (#730): pin exact items while searching, then walk the
# house with a box-grouped picking list that strikes itself off as items get
# unpacked. Personal rows only — every query is keyed (move, current_user), so
# members never see each other's pins, and there is deliberately NO writable-
# Move gate on the pin rows: a viewer helping unpack and an archived Move's
# members may pin (the actions document the same decision). The exception is
# mark_found/restore (#735) — those flip the shared Item's presence, so they
# take the standard writable gate like every other Item mutation. Membership is
# still enforced by MoveScopedController's Move scoping (non-members 404).
# Thin: load, call the action, stream.
class FindListsController < MoveScopedController
  include TurboStreamable

  before_action { Current.nav_section = :search }
  before_action :set_item, only: %i[pin unpin mark_found restore]
  before_action :require_writable_move!, only: %i[mark_found restore]

  # GET /moves/:move_id/find_list

  #: () -> untyped
  def show
    render Views::FindLists::Show.new(move: @move, entries: rollup, editable: editable_move?)
  end

  # POST /moves/:move_id/find_list/items/:item_id

  #: () -> untyped
  def pin
    FindLists::Pin.new.call(move: @move, user: current_user, item: @item)
    # A pin lands off-screen (the list page) — UX rule 1 wants a LINKING
    # confirmation (Codex #733): the toast carries a View-list action.
    # flash.now scopes it to the stream render; the HTML fallback needs none —
    # its redirect lands ON the list.
    flash.now[:action_href] = move_find_list_path(@move)
    flash.now[:action_label] = t("find_lists.flash.view")
    respond_with_streams(toggle_streams(pinned: true),
                         redirect: move_find_list_path(@move), toast: true) do
      [:notice, t("find_lists.flash.pinned", name: @item.name)]
    end
  end

  # DELETE /moves/:move_id/find_list/items/:item_id

  #: () -> untyped
  def unpin
    FindLists::Unpin.new.call(move: @move, user: current_user, item: @item)
    respond_with_streams(toggle_streams(pinned: false), redirect: move_find_list_path(@move))
  end

  # PATCH /moves/:move_id/find_list/items/:item_id/found
  # Marks the pinned item unpacked in place. The action guards the pin (its
  # phase bypass is only as wide as "retrieving this pinned item" — Codex
  # #736) and delegates to Items::MarkRemoved. The strike itself needs no
  # toast (the row striking, the Found chip, and the summary count ARE the
  # feedback — checklist precedent), but when the action ALSO auto-opened the
  # box (#738) that secondary mutation is off-screen, so it surfaces with a
  # linking toast (UX rule 1 — the pin toast's pattern).

  #: () -> untyped
  def mark_found
    case result = FindLists::MarkFound.new.call(move: @move, user: current_user, item: @item)
    in Dry::Monads::Success({ opened_box: Box => box })
      # The link must survive BOTH paths: flash.now scopes it to the stream
      # render, while the no-JS fallback REDIRECTS — there it rides the
      # persistent flash for exactly one request (Codex #739).
      link_flash = request.format.turbo_stream? ? flash.now : flash
      link_flash[:action_href] = move_box_path(@move, box)
      link_flash[:action_label] = t("find_lists.flash.view_box")
      respond_with_streams([list_stream], redirect: move_find_list_path(@move), toast: true) do
        [:notice, t("find_lists.flash.box_opened", number: box.number)]
      end
    else
      respond_to_found_toggle(result)
    end
  end

  # PATCH /moves/:move_id/find_list/items/:item_id/restore — the undo.

  #: () -> untyped
  def restore
    respond_to_found_toggle(FindLists::Restore.new.call(move: @move, user: current_user, item: @item))
  end

  # DELETE /moves/:move_id/find_list/found

  #: () -> untyped
  def clear_found
    result = FindLists::ClearFound.new.call(move: @move, user: current_user)
    count = result.value_or(0) #: Integer
    respond_with_streams([list_stream], redirect: move_find_list_path(@move), toast: true) do
      [:notice, t("find_lists.flash.cleared", count: count)]
    end
  end

  private

  # ONE response serves every surface the toggle can live on (search card,
  # item detail, the box contents grid — icon on standalone cards, chip on
  # photo cards (#747) — the list page, the search pill): Turbo silently
  # no-ops a replace whose target is absent, so no origin params are needed.
  # Each render is a few personal rows — cheap.

  #: (pinned: bool) -> Array[untyped]
  def toggle_streams(pinned:)
    Components::FindLists::Toggle::VARIANTS.map do |variant|
      turbo_stream.replace(
        Components::FindLists::Toggle.dom_id(@item, variant: variant),
        view_context.render(Components::FindLists::Toggle.new(move: @move, item: @item, pinned: pinned,
                                                              variant: variant))
      )
    end + [search_link_stream, list_stream]
  end

  #: () -> untyped
  def search_link_stream
    # :item join (kept scope): dangling pins never inflate the pill count.
    count = FindListEntry.where(move_id: @move.id, user_id: current_user.id).joins(:item).count
    turbo_stream.replace(
      Components::FindLists::SearchLink::ID,
      view_context.render(Components::FindLists::SearchLink.new(move: @move, count: count))
    )
  end

  #: (untyped result) -> untyped
  def respond_to_found_toggle(result)
    case result
    in Dry::Monads::Success(_) | Dry::Monads::Failure(:not_pinned) | Dry::Monads::Failure(:box_unpacked)
      # :not_pinned / :box_unpacked = a stale form (unpinned or the box
      # completed on another device) or a crafted URL — nothing mutated;
      # re-rendering reality makes the stale row/control disappear, which is
      # the same response the success needs.
      respond_with_streams([list_stream], redirect: move_find_list_path(@move))
    in Dry::Monads::Failure(_)
      # Unreachable in practice (require_writable_move! fences archived; the
      # presence flip cannot fail validation) — kept so a raced archive
      # degrades to a friendly redirect instead of a NoMatchingPatternError.
      redirect_to move_find_list_path(@move), alert: t("moves.archived_alert")
    end
  end

  #: () -> untyped
  def list_stream
    turbo_stream.replace(
      Components::FindLists::List::ID,
      view_context.render(Components::FindLists::List.new(move: @move, entries: rollup,
                                                          editable: editable_move?))
    )
  end

  #: () -> untyped
  def rollup
    FindListEntry.rollup_for(@move, current_user)
  end

  # Kept items only (Item's default scope): pinning a discarded/foreign item 404s.

  #: () -> untyped
  def set_item
    @item = @move.items.find(params.expect(:item_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # Archived-Move redirect target (require_writable_move!) — back to the
  # (read-only) find list rather than the boxes home.

  #: () -> String
  def read_only_redirect_path
    move_find_list_path(@move)
  end
end
