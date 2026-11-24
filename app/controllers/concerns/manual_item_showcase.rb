# frozen_string_literal: true

# The #958 "make the new item unmissable" landing for ItemsController#create
# (UX rule 1), mirroring BoxesController#redirect_to_index_showcasing: back on
# the box page with a "View item" link in the toast + a one-time highlight that
# scrolls the new card into view. Standalone cards render after every photo
# card, so in a photo-heavy box the new item would otherwise sit below the fold.
# BoxesController#show reads `flash[:highlight_item_id]` and the card connects
# the shared `highlight` Stimulus controller. Expects @move and @box.
# NB: concern modules are unchecked by Steep (Steepfile note); this module's
# surface is declared in sig/concerns.rbs like the other controller concerns.
module ManualItemShowcase
  extend ActiveSupport::Concern

  private

  def redirect_to_box_showcasing(item)
    flash[:action_href] = move_item_path(@move, item)
    flash[:action_label] = t("items.create.view_item")
    flash[:highlight_item_id] = item.id
    redirect_to move_box_path(@move, @box), notice: t("items.create.created", name: item.name)
  end
end
