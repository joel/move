# frozen_string_literal: true

module Views
  module Items
    # C3 — Item detail / edit. Two-column on desktop: source media (full image,
    # never cropped) on the left; the edit form plus Move and Remove/Restore
    # controls on the right. Review and presence are shown as independent axes.
    class Show < Views::Base
      #: (move: untyped, item: untyped, boxes: untyped, ?editable: untyped, ?photo_siblings: untyped, ?group_siblings: untyped) -> void
      def initialize(move:, item:, boxes:, editable: false, photo_siblings: 0, group_siblings: nil)
        @move = move
        @item = item
        @boxes = boxes
        @editable = editable
        # Count of *other* in-box items detected in this item's source photo (0 for
        # manual items) — surfaces the one-photo → many-items relationship on C3.
        @photo_siblings = photo_siblings
        # The item's cluster family (#642), or nil when it's in no group —
        # surfaces the cross-box relationship the one-photo note can't.
        @group_siblings = group_siblings
      end

      #: () -> void
      def view_template
        back_link
        header
        div(class: "grid grid-cols-1 gap-stack-gap lg:grid-cols-12") do
          media_panel
          edit_panel
        end
        group_rail if @group_siblings
      end

      private

      #: () -> untyped
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

      #: () -> untyped
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

      #: () -> untyped
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

      #: () -> untyped
      def sibling_note
        return unless @photo_siblings.positive?

        p(class: "mt-3 text-body-md text-muted") do
          I18n.t("items.show.from_same_photo", count: @photo_siblings)
        end
      end

      #: () -> untyped
      def media_image
        if @item.source_media&.image_displayable?
          img(
            src: MediaVariants::TransformUrl.for(@item.source_media, :detail),
            class: "aspect-square w-full object-cover", alt: "", loading: "lazy"
          )
        elsif @item.source_media&.image_unavailable?
          unavailable_placeholder
        else
          div(class: "flex aspect-square w-full items-center justify-center text-muted") do
            render Components::Icons::Camera.new(css: "h-10 w-10")
          end
        end
      end

      # Master blob unrecoverable (#563) — the item data is intact, only the photo
      # is gone.

      #: () -> untyped
      def unavailable_placeholder
        div(class: "flex aspect-square w-full flex-col items-center justify-center gap-2 text-muted") do
          render Components::Icons::ImageOff.new(css: "h-10 w-10")
          span(class: "text-body-md") { I18n.t("ui.media.unavailable") }
        end
      end

      #: () -> untyped
      def state_badges
        render Components::Items::StateBadges.new(item: @item)
      end

      #: () -> untyped
      def box_caption
        div(class: "absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/60 to-transparent p-3") do
          span(class: "text-label-caps uppercase text-white") { box_context(@item.box) }
        end
      end

      # --- Right: edit + move + remove --------------------------------------

      #: () -> untyped
      def edit_panel
        section(class: "lg:col-span-7") do
          render Components::Ui::Card.new(padding: "p-6") do
            @editable ? editable_body : read_only_body
          end
        end
      end

      #: () -> untyped
      def editable_body
        render Components::ItemForm.new(models: [@move, @item], item: @item, autosave: true)
        render Components::Items::PresenceControls.new(
          move: @move, item: @item, boxes: @boxes, editable: @editable
        )
      end

      # Read-only detail for viewers / archived Moves: the item name, rendered as
      # labelled text instead of an input.

      #: () -> untyped
      def read_only_body
        div(class: "flex flex-col gap-5") do
          detail_row(I18n.t("items.form.name"), @item.name)
          p(class: "border-t border-card-border pt-4 text-body-md text-muted") do
            I18n.t(@move.archived? ? "items.show.archived" : "items.show.view_only")
          end
        end
      end

      #: (untyped label, untyped value) -> untyped
      def detail_row(label, value)
        div(class: "flex flex-col gap-1") do
          span(class: "text-label-caps uppercase text-muted") { label }
          span(class: "text-body-lg text-text-warm") { value }
        end
      end

      #: (untyped box) -> String
      def box_context(box)
        number = Kernel.format("%03d", box.number.to_i)
        room = box.room&.name
        room ? "#{I18n.t("items.box", number:)} · #{room}" : I18n.t("items.box", number:)
      end

      # --- "In the same group" rail (#642) -----------------------------------

      # The item's cluster family — the other members, scattered across boxes.
      # Surfaces the cross-box relationship (batteries in the kitchen box AND
      # the office box) that the one-photo sibling note above can't; the header
      # links to the full group, each row to that member's own detail page.

      #: () -> untyped
      def group_rail
        section(class: "mt-section-gap flex flex-col gap-3") do
          rail_header
          ul(class: "flex flex-col gap-2") do
            @group_siblings.items.each { |sibling| sibling_row(sibling) }
          end
        end
      end

      #: () -> untyped
      def rail_header
        a(
          href: move_gallery_group_path(@move, @group_siblings.cluster),
          class: "flex items-baseline justify-between gap-3 transition hover:text-accent-sage"
        ) do
          span(class: "text-label-caps uppercase text-muted") { I18n.t("items.show.same_group") }
          span(class: "text-body-md text-accent-sage") { I18n.t("items.show.view_group") }
        end
      end

      #: (untyped sibling) -> untyped
      def sibling_row(sibling)
        li do
          a(
            href: move_item_path(@move, sibling),
            class: "flex items-center gap-3 rounded-card border border-card-border bg-card p-3 " \
                   "transition hover:border-accent-sage focus:outline-none " \
                   "focus:ring-2 focus:ring-accent-sage/40"
          ) do
            sibling_thumb(sibling)
            span(class: "min-w-0 flex-1 truncate text-body-md text-text-warm") { sibling.name }
            render Components::Ui::Chip.new(label: box_context(sibling.box), kind: :category)
          end
        end
      end

      #: (untyped sibling) -> untyped
      def sibling_thumb(sibling)
        div(class: "flex h-12 w-12 flex-shrink-0 items-center justify-center overflow-hidden " \
                   "rounded-lg bg-surface-container-high text-muted") do
          media = sibling.source_media
          if media&.image_displayable?
            img(
              src: MediaVariants::TransformUrl.for(media, :thumb),
              alt: "", loading: "lazy", class: "h-full w-full object-cover"
            )
          else
            render Components::Icons::Camera.new(css: "h-5 w-5 opacity-40")
          end
        end
      end
    end
  end
end
