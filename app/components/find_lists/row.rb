# frozen_string_literal: true

module Components
  module FindLists
    # One pinned item on the find list (#730, #735): item link (thumb + name,
    # struck once the item is unpacked) inside a Ui::SwipeActions card — below
    # lg, swiping reveals mark-found/restore (leading) and unpin (trailing); at
    # lg+ the inline controls stay. The li keeps the stable per-entry DOM id
    # (the stream anchor — SwipeActions renders a div), and every control
    # carries a stable button id so refocus keeps keyboard focus across the
    # full-list replace. Mark-found/restore mutate the shared Item, so they are
    # gated on editable:; unpin is a personal row and always offered.
    class Row < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      # @rbs skip
      def self.dom_id(entry)
        "find-list-entry-#{entry.id}"
      end

      #: (move: untyped, entry: untyped, editable: untyped) -> void
      def initialize(move:, entry:, editable:)
        @move = move
        @entry = entry
        @item = entry.item
        @editable = editable
      end

      #: () -> void
      def view_template
        li(id: self.class.dom_id(@entry)) do
          render Components::Ui::SwipeActions.new(
            css: "rounded-card border border-card-border bg-card",
            content_css: "flex items-center gap-3 p-3",
            leading: (found_action if @editable),
            trailing: unpin_action
          ) do
            item_link
            found_chip if found?
            inline_actions
          end
        end
      end

      private

      #: () -> bool
      def found?
        @item.removed?
      end

      #: () -> untyped
      def item_link
        a(href: view_context.move_item_path(@move, @item),
          class: "flex min-w-0 flex-1 items-center gap-3 transition hover:text-accent-sage") do
          thumb
          span(class: "min-w-0 flex-1 truncate text-body-md " \
                      "#{found? ? "text-muted line-through" : "text-text-warm"}") { @item.name }
        end
      end

      #: () -> untyped
      def thumb
        div(class: "relative flex h-12 w-12 flex-shrink-0 items-center justify-center overflow-hidden " \
                   "rounded-lg bg-surface-container-high text-muted") do
          media = @item.source_media
          if media&.image_displayable?
            render Components::Ui::BlurUpImage.new(
              src: MediaVariants::TransformUrl.for(media, :thumb), lqip: media.image_lqip,
              loading: "lazy", decoding: "async", img_class: "h-full w-full object-cover"
            )
          else
            render Components::Icons::Boxes.new(css: "h-5 w-5 opacity-40")
          end
        end
      end

      # The struck state borrows E3's checked treatment at chip scale.

      #: () -> untyped
      def found_chip
        span(class: "inline-flex shrink-0 items-center gap-1 rounded-full bg-accent-sage/90 " \
                    "px-2 py-0.5 text-label-caps uppercase text-page") do
          render Components::Icons::Check.new(css: "h-3 w-3")
          plain I18n.t("find_lists.show.found")
        end
      end

      # Swipe-right (leading) option: one control that flips with the item's
      # presence — mark found when in_box, restore when already found. Sage
      # tint both ways (restore is not destructive).

      #: () -> untyped
      def found_action
        lambda do |_c|
          button_to(
            found_toggle_path,
            method: :patch, form_class: "contents",
            id: "find-list-swipe-found-#{@item.id}",
            aria: { label: found_toggle_label },
            class: "#{Components::Ui::SwipeActions::OPTION_CLASSES} bg-accent-sage/15 text-accent-sage"
          ) do
            render found_toggle_icon.new(css: "h-5 w-5")
            span(class: "text-label-caps uppercase") { found_toggle_short }
          end
        end
      end

      # Swipe-left (trailing) option: the same DELETE unpin as the inline ×.
      # Close icon, not Trash — unpin drops the pin, it deletes no data.

      #: () -> untyped
      def unpin_action
        lambda do |_c|
          button_to(
            unpin_path,
            method: :delete, form_class: "contents",
            id: "find-list-swipe-unpin-#{@item.id}",
            aria: { label: I18n.t("find_lists.toggle.remove", name: @item.name) },
            class: "#{Components::Ui::SwipeActions::OPTION_CLASSES} bg-error text-on-error"
          ) do
            render Components::Icons::Close.new(css: "h-5 w-5")
            span(class: "text-label-caps uppercase") { I18n.t("find_lists.row.remove_short") }
          end
        end
      end

      #: () -> untyped
      def inline_actions
        div(class: "hidden shrink-0 items-center gap-1 lg:flex") do
          found_toggle_control if @editable
          unpin_control
        end
      end

      # One shared stable id across both states: after the full-list replace the
      # refocus controller lands keyboard focus back on the flipped toggle (the
      # box detail's unpack-item- pattern).

      #: () -> untyped
      def found_toggle_control
        button_to(
          found_toggle_path,
          method: :patch, id: "find-list-row-found-#{@item.id}",
          class: "flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-muted " \
                 "transition hover:bg-accent-sage/10 hover:text-accent-sage",
          aria: { label: found_toggle_label }, title: found_toggle_label
        ) { render found_toggle_icon.new(css: "h-4 w-4") }
      end

      #: () -> untyped
      def unpin_control
        button_to(
          unpin_path,
          method: :delete, id: "find-list-row-unpin-#{@item.id}",
          class: "flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-muted " \
                 "transition hover:bg-surface-container-high hover:text-error",
          aria: { label: I18n.t("find_lists.toggle.remove", name: @item.name) },
          title: I18n.t("find_lists.toggle.remove", name: @item.name)
        ) { render Components::Icons::Close.new(css: "h-4 w-4") }
      end

      #: () -> untyped
      def found_toggle_path
        if found?
          view_context.move_find_list_restore_path(@move, item_id: @item.id)
        else
          view_context.move_find_list_mark_found_path(@move, item_id: @item.id)
        end
      end

      #: () -> untyped
      def found_toggle_icon
        found? ? Components::Icons::Retry : Components::Icons::Check
      end

      #: () -> untyped
      def found_toggle_label
        I18n.t(found? ? "find_lists.row.restore" : "find_lists.row.mark_found", name: @item.name)
      end

      #: () -> untyped
      def found_toggle_short
        I18n.t(found? ? "find_lists.row.restore_short" : "find_lists.row.found_short")
      end

      #: () -> untyped
      def unpin_path
        view_context.move_find_list_unpin_path(@move, item_id: @item.id)
      end
    end
  end
end
