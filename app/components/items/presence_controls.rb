# frozen_string_literal: true

module Components
  module Items
    # C3 — the right-column footer controls: Move (to another box) and the
    # presence action (Restore / Mark-unpacked / Delete), whose meaning flips with
    # the item's presence and the box's lifecycle phase. Stable id so
    # items#mark_removed / #restore can Turbo-replace it after a presence change —
    # Move hides while removed, and the presence button swaps — with no reload.
    class PresenceControls < Components::Base
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::FormWith

      ID = "item-presence-controls"

      def initialize(move:, item:, boxes:, editable:)
        @move = move
        @item = item
        @boxes = boxes
        @editable = editable
      end

      def view_template
        div(id: ID, class: "mt-2 flex flex-wrap items-center gap-3 border-t border-card-border pt-5") do
          if @editable
            move_control
            presence_control
          end
        end
      end

      private

      def move_control
        # A removed item must be restored before it can be moved — hide Move while
        # removed (the footer shows Restore instead).
        return if @item.removed?

        targets = @boxes.reject { |b| b.id == @item.box_id }
        return if targets.empty?

        form_with(url: move_move_item_path(@move, @item), method: :patch,
                  class: "flex items-center gap-2") do
          select(
            name: "target_box_id",
            class: "rounded-card border border-card-border bg-card px-3 py-2 text-text-warm"
          ) do
            targets.each { |b| option(value: b.id) { box_context(b) } }
          end
          button(type: "submit", class: ghost_button) { I18n.t("items.show.move") }
        end
      end

      # The remove control's meaning depends on where the box is in its lifecycle.
      # A *removed* item always offers Restore-to-box — that presence inverse is its
      # only C3 undo, regardless of phase. Otherwise: while unpacking/unpacked,
      # removing means "physically taken out" (presence → removed, reversible);
      # while *packing*, the item was added by mistake — Delete it. A sealed /
      # in-transit box is closed: no removal control — unseal it to edit contents.
      def presence_control
        if @item.removed?
          restore_to_box_control
        elsif @item.box.unpacking? || @item.box.unpacked?
          mark_unpacked_control
        elsif @item.box.packing?
          delete_control
        end
      end

      def restore_to_box_control
        button_to(
          I18n.t("items.show.restore"), restore_move_item_path(@move, @item),
          method: :patch, class: ghost_button
        )
      end

      def mark_unpacked_control
        button_to(
          I18n.t("items.show.mark_unpacked"), mark_removed_move_item_path(@move, @item),
          method: :patch, class: danger_button,
          data: { turbo_confirm: I18n.t("items.show.mark_unpacked_confirm") }
        )
      end

      def delete_control
        button_to(
          I18n.t("items.show.delete"), move_item_path(@move, @item),
          method: :delete, class: danger_button,
          data: { turbo_confirm: I18n.t("items.show.delete_confirm") }
        )
      end

      def ghost_button
        "inline-flex items-center justify-center gap-2 rounded-full px-5 py-2 text-sm " \
          "font-bold text-text-warm transition hover:bg-surface-container-high active:scale-[0.98]"
      end

      # Destructive action — filled error red (mirrors Ui::Button :danger variant).
      def danger_button
        "inline-flex items-center justify-center gap-2 rounded-full px-5 py-2 text-sm " \
          "font-bold bg-error text-on-error transition hover:opacity-90 active:scale-[0.98]"
      end

      def box_context(box)
        number = Kernel.format("%03d", box.number.to_i)
        room = box.room&.name
        room ? "#{I18n.t("items.box", number:)} · #{room}" : I18n.t("items.box", number:)
      end
    end
  end
end
