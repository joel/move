# frozen_string_literal: true

module Views
  module Items
    # C3 — Item detail / edit. Two-column on desktop: source media (full image,
    # never cropped) on the left; the edit form plus Move and Remove/Restore
    # controls on the right. Review and presence are shown as independent axes.
    class Show < Views::Base
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::FormWith

      def initialize(move:, item:, boxes:, categories:, tags:)
        @move = move
        @item = item
        @boxes = boxes
        @categories = categories
        @tags = tags
      end

      def view_template
        back_link
        header
        div(class: "grid grid-cols-1 gap-stack-gap lg:grid-cols-12") do
          media_panel
          edit_panel
        end
      end

      private

      def back_link
        a(
          href: move_box_path(@move, @item.box),
          class: "inline-flex items-center gap-2 text-label-caps uppercase text-muted hover:text-text-warm"
        ) do
          render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-180")
          plain I18n.t("items.show.back")
        end
      end

      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: box_context(@item.box), title: I18n.t("items.show.title")
        )
      end

      # --- Left: source media ------------------------------------------------
      def media_panel
        section(class: "lg:col-span-5") do
          div(class: "relative overflow-hidden rounded-card border border-card-border bg-surface-container-high") do
            state_badges
            media_image
            box_caption
          end
        end
      end

      def media_image
        if @item.source_media&.image&.attached?
          img(
            src: view_context.rails_storage_proxy_path(@item.source_media.image),
            class: "aspect-square w-full object-cover", alt: "", loading: "lazy"
          )
        else
          div(class: "flex aspect-square w-full items-center justify-center text-muted") do
            render Components::Icons::Camera.new(css: "h-10 w-10")
          end
        end
      end

      def state_badges
        div(class: "absolute left-3 top-3 z-10 flex flex-wrap gap-2") do
          render Components::Ui::Chip.new(
            label: I18n.t("items.state.#{@item.review_state}"), kind: review_kind
          )
          render Components::Ui::Chip.new(label: I18n.t("items.presence.removed"), kind: :tag) if @item.removed?
        end
      end

      def box_caption
        div(class: "absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/60 to-transparent p-3") do
          span(class: "text-label-caps uppercase text-white") { box_context(@item.box) }
        end
      end

      # --- Right: edit + move + remove --------------------------------------
      def edit_panel
        section(class: "lg:col-span-7") do
          render Components::Ui::Card.new(padding: "p-6") do
            render Components::ItemForm.new(
              models: [@move, @item], item: @item,
              categories: @categories, tags: @tags,
              submit_label: I18n.t("items.show.save")
            )
            div(class: "mt-2 flex flex-wrap items-center gap-3 border-t border-card-border pt-5") do
              move_control
              presence_control
            end
          end
        end
      end

      def move_control
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

      def presence_control
        if @item.removed?
          button_to(
            I18n.t("items.show.restore"), restore_move_item_path(@move, @item),
            method: :patch, class: ghost_button
          )
        else
          button_to(
            I18n.t("items.show.remove"), mark_removed_move_item_path(@move, @item),
            method: :patch, class: ghost_button,
            data: { turbo_confirm: I18n.t("items.show.remove_confirm") }
          )
        end
      end

      def ghost_button
        "inline-flex items-center justify-center gap-2 rounded-full px-5 py-2 text-sm " \
          "font-bold text-text-warm transition hover:bg-surface-container-high active:scale-[0.98]"
      end

      def box_context(box)
        number = Kernel.format("%03d", box.number.to_i)
        room = box.room&.name
        room ? "#{I18n.t("items.box", number:)} · #{room}" : I18n.t("items.box", number:)
      end

      def review_kind
        @item.review_state == "pending_review" ? :tag : :room
      end
    end
  end
end
