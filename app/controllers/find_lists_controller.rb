# frozen_string_literal: true

# The personal find list (#730): pin exact items while searching, then walk the
# house with a box-grouped picking list that strikes itself off as items get
# unpacked. Personal rows only — every query is keyed (move, current_user), so
# members never see each other's pins, and there is deliberately NO writable-
# Move gate: a viewer helping unpack and an archived Move's members may pin
# (the actions document the same decision). Membership is still enforced by
# MoveScopedController's Move scoping (non-members 404). Thin: load, call the
# action, stream.
class FindListsController < MoveScopedController
  include TurboStreamable

  before_action { Current.nav_section = :search }
  before_action :set_item, only: %i[pin unpin]

  # GET /moves/:move_id/find_list

  #: () -> untyped
  def show
    render Views::FindLists::Show.new(move: @move, entries: rollup)
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
  # item detail, the list page, the search pill): Turbo silently no-ops a
  # replace whose target is absent, so no origin params are needed. Each render
  # is a few personal rows — cheap.

  #: (pinned: bool) -> Array[untyped]
  def toggle_streams(pinned:)
    [
      turbo_stream.replace(
        Components::FindLists::Toggle.dom_id(@item),
        view_context.render(Components::FindLists::Toggle.new(move: @move, item: @item, pinned: pinned))
      ),
      turbo_stream.replace(
        Components::FindLists::Toggle.dom_id(@item, labeled: true),
        view_context.render(Components::FindLists::Toggle.new(move: @move, item: @item, pinned: pinned,
                                                              labeled: true))
      ),
      search_link_stream,
      list_stream
    ]
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

  #: () -> untyped
  def list_stream
    turbo_stream.replace(
      Components::FindLists::List::ID,
      view_context.render(Components::FindLists::List.new(move: @move, entries: rollup))
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
end
