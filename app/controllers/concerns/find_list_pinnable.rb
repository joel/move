# frozen_string_literal: true

# The find-list pin gate shared by the box-scoped surfaces that render the
# per-item pin toggle — the contents grid (#747) and the review rows (#749).
# A closed (sealed/in-transit) box is retrieval planning, so exactly those
# states show the pin; deliberately NOT editable-gated — viewers may pin
# (personal rows only; FindLists::Pin documents the decision). Expects the
# including controller to set @move and @box (MoveScopedController pattern).
# NB: concern modules are unchecked by Steep (Steepfile note); this module's
# surface is declared in sig/concerns.rbs like the other controller concerns.
module FindListPinnable
  extend ActiveSupport::Concern

  private

  def pinnable? = @box.closed?

  # The current user's pins, Move-wide, as a per-request membership set.
  # Empty (no query) when not pinnable.
  def pinned_item_ids
    @pinned_item_ids ||= pinnable? ? FindListEntry.pinned_item_ids_for(move: @move, user: current_user) : Set.new
  end
end
