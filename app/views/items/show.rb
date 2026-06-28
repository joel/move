# frozen_string_literal: true

module Views
  module Items
    # C3 — Item detail / edit. Two-column on desktop: source media (full image,
    # never cropped) on the left; the edit form plus Move and Remove/Restore
    # controls on the right. Review and presence are shown as independent axes.
    class Show < Views::Base
      def initialize(move:, item:, boxes:, categories:, tags:, editable: false, photo_siblings: 0)
        @move = move
        @item = item
        @boxes = boxes
        @categories = categories
        @tags = tags
        @editable = editable
        # Count of *other* in-box items detected in this item's source photo (0 for
        # manual items) — surfaces the one-photo → many-items relationship on C3.
        @photo_siblings = photo_siblings
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
        href = move_box_path(@move, @item.box)
        label = I18n.t("items.show.back")
        a(
          href: href,
          class: "inline-flex items-center gap-2 text-label-caps uppercase text-muted hover:text-text-warm"
        ) do
          render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-180")
          plain label
        end
      end

      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: box_context(@item.box), title: I18n.t("items.show.title")
        ) do
          # Inline auto-save indicator (C3 has no Save button); replaced by the
          # items#update Turbo Stream after each field change.
          render Components::Ui::SaveStatus.new if @editable
        end
      end

      # --- Left: source media ------------------------------------------------
      def media_panel
        section(class: "lg:col-span-5") do
          div(class: "relative overflow-hidden rounded-card border border-card-border bg-surface-container-high") do
            state_badges
            media_image
            box_caption
          end
          sibling_note
        end
      end

      # "Detected with N other items in this photo" — only when this item came from
      # a photo that yielded more than one in-box item.
      def sibling_note
        return unless @photo_siblings.positive?

        p(class: "mt-3 text-body-md text-muted") do
          I18n.t("items.show.from_same_photo", count: @photo_siblings)
        end
      end

      def media_image
        if @item.source_media&.image&.attached?
          img(
            src: view_context.rails_storage_proxy_path(@item.source_media.image.variant(:detail)),
            class: "aspect-square w-full object-cover", alt: "", loading: "lazy"
          )
        else
          div(class: "flex aspect-square w-full items-center justify-center text-muted") do
            render Components::Icons::Camera.new(css: "h-10 w-10")
          end
        end
      end

      def state_badges
        render Components::Items::StateBadges.new(item: @item)
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
            @editable ? editable_body : read_only_body
          end
        end
      end

      def editable_body
        render Components::ItemForm.new(
          models: [@move, @item], item: @item,
          categories: @categories, tags: @tags, autosave: true
        )
        render Components::Items::PresenceControls.new(
          move: @move, item: @item, boxes: @boxes, editable: @editable
        )
      end

      # Read-only detail for viewers / archived Moves: the same attributes the
      # form edits, rendered as labelled text instead of inputs/controls.
      def read_only_body
        div(class: "flex flex-col gap-5") do
          detail_row(I18n.t("items.form.name"), @item.name)
          detail_row(I18n.t("items.form.quantity"), @item.quantity.to_s)
          detail_row(I18n.t("items.form.category"), @item.category&.name || "—")
          detail_row(I18n.t("items.form.tags"), item_tag_labels)
          p(class: "border-t border-card-border pt-4 text-body-md text-muted") do
            I18n.t(@move.archived? ? "items.show.archived" : "items.show.view_only")
          end
        end
      end

      def detail_row(label, value)
        div(class: "flex flex-col gap-1") do
          span(class: "text-label-caps uppercase text-muted") { label }
          span(class: "text-body-lg text-text-warm") { value }
        end
      end

      def item_tag_labels
        names = @item.tags.map(&:name)
        names.any? ? names.join(", ") : "—"
      end

      def box_context(box)
        number = Kernel.format("%03d", box.number.to_i)
        room = box.room&.name
        room ? "#{I18n.t("items.box", number:)} · #{room}" : I18n.t("items.box", number:)
      end
    end
  end
end
