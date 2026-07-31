# frozen_string_literal: true

module Components
  module Reviews
    # C2 — one detected-item row in the per-photo review list: an inline-rename
    # name field (auto-saves on blur), a confidence/added caption, and pencil/×
    # actions. Carries a stable per-item DOM id so ReviewsController can
    # turbo_stream.remove it when the reviewer drops a mis-detection, and so a
    # freshly-added item can stream in (highlighted) without a reload.
    class ItemRow < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      # @rbs skip
      def self.dom_id(item)
        "review-item-#{item.id}"
      end

      # highlight: the row just streamed in from an add — scroll it into view and
      # flash a ring (UX rule #1) via the shared `highlight` Stimulus controller.
      # queue: the Move-wide walk (#654) — the remove URL carries ?queue=move so
      # its no-JS fallback redirects back into the walk (rename never navigates).
      # pinnable/pinned (#749, closed box): the find-list pin toggle in the row —
      # personal state, deliberately not editable-gated (viewers pin), and NOT in
      # the swipe layers so it stays reachable on touch without a gesture.

      # @rbs move: untyped
      # @rbs box: untyped
      # @rbs media: untyped
      # @rbs item: untyped
      # @rbs editable: untyped
      # @rbs highlight: untyped
      # @rbs queue: untyped
      # @rbs pinnable: bool
      # @rbs pinned: bool
      # @rbs return: void
      def initialize(move:, box:, media:, item:, editable:, highlight: false, queue: false,
                     pinnable: false, pinned: false)
        @move = move
        @box = box
        @media = media
        @item = item
        @editable = editable
        @highlight = highlight
        @queue = queue
        @pinnable = pinnable
        @pinned = pinned
      end

      # Below lg the pencil/× are swipe-revealed (Ui::SwipeActions layers);
      # at lg+ the inline row_actions stay, so the desktop row is unchanged.

      #: () -> void
      def view_template
        render Components::Ui::SwipeActions.new(
          id: self.class.dom_id(@item), data: row_data,
          css: "group rounded-card border border-card-border bg-card " \
               "transition focus-within:border-accent-sage",
          content_css: "flex items-center gap-3 p-4",
          leading: (edit_action if @editable),
          trailing: (remove_action if @editable)
        ) do
          div(class: "flex flex-1 flex-col gap-1") do
            name_field
            confidence_line
          end
          pin_toggle if @pinnable
          row_actions if @editable
        end
      end

      private

      #: () -> untyped
      def row_data
        controllers = []
        controllers << "inline-rename" if @editable
        controllers << "highlight" if @highlight
        return {} if controllers.empty?

        data = { controller: controllers.join(" ") }
        data[:inline_rename_url_value] = rename_path if @editable
        data
      end

      #: () -> untyped
      def name_field
        input(
          type: "text", value: @item.name, readonly: !@editable,
          aria_label: I18n.t("reviews.photo.name"), data: name_field_data,
          class: "w-full border-0 bg-transparent p-0 text-body-lg text-text-warm focus:ring-0"
        )
      end

      #: () -> untyped
      def name_field_data
        return {} unless @editable

        { inline_rename_target: "input",
          action: "focus->inline-rename#clearError blur->inline-rename#save keydown.enter->inline-rename#blur" }
      end

      #: () -> untyped
      def confidence_line
        div(class: "flex items-center gap-1.5") do
          if (pct = confidence_percent)
            span(class: "h-1.5 w-1.5 rounded-full bg-accent-sage")
            span(class: "text-label-caps uppercase text-muted") do
              I18n.t("reviews.photo.confidence", percent: pct)
            end
          else
            span(class: "text-label-caps uppercase text-muted") { I18n.t("reviews.photo.added") }
          end
        end
      end

      # The find-list pin (#749) — the shared icon Toggle, whose dom_id is what
      # FindListsController's toggle streams already target, so pin/unpin from
      # any surface flips this row's control in place.

      #: () -> untyped
      def pin_toggle
        div(class: "shrink-0") do
          render Components::FindLists::Toggle.new(move: @move, item: @item, pinned: @pinned)
        end
      end

      #: () -> untyped
      def row_actions
        div(class: "hidden shrink-0 items-center gap-1 lg:flex") do
          button(type: "button", data: { action: "inline-rename#focus" }, class: icon_button(:sage)) do
            render Components::Icons::Pencil.new(css: "h-5 w-5")
            span(class: "sr-only") { I18n.t("reviews.photo.edit") }
          end
          button_to(
            remove_path,
            method: :patch, class: icon_button(:error), form_class: "shrink-0"
          ) do
            render Components::Icons::Close.new(css: "h-5 w-5")
            span(class: "sr-only") { I18n.t("reviews.photo.remove_named", name: @item.name) }
          end
        end
      end

      # Swipe-right (leading) option: closes the row and focuses the
      # inline-rename input — both controllers share the wrapper scope.

      #: () -> untyped
      def edit_action
        lambda do |_c|
          button(
            type: "button", aria_label: I18n.t("reviews.photo.edit"),
            data: { action: "swipe-actions#close inline-rename#focus" },
            class: "#{Components::Ui::SwipeActions::OPTION_CLASSES} bg-accent-sage/15 text-accent-sage"
          ) do
            render Components::Icons::Pencil.new(css: "h-5 w-5")
            span(class: "text-label-caps uppercase") { I18n.t("reviews.photo.swipe_edit") }
          end
        end
      end

      # Swipe-left (trailing) option: the same PATCH remove as the desktop ×.
      # The visible label is the short "Remove"; the full accessible name
      # (remove_named) rides an aria-label so the desktop button stays the
      # unique Capybara match for it.

      #: () -> untyped
      def remove_action
        lambda do |_c|
          button_to(
            remove_path,
            method: :patch, form_class: "contents",
            aria: { label: I18n.t("reviews.photo.remove_named", name: @item.name) },
            class: "#{Components::Ui::SwipeActions::OPTION_CLASSES} bg-error text-on-error"
          ) do
            render Components::Icons::Trash.new(css: "h-5 w-5")
            span(class: "text-label-caps uppercase") { I18n.t("reviews.photo.swipe_remove") }
          end
        end
      end

      #: (untyped tint) -> untyped
      def icon_button(tint)
        hover = tint == :error ? "hover:text-error hover:bg-error/10" : "hover:text-accent-sage hover:bg-accent-sage/10"
        "flex h-10 w-10 items-center justify-center rounded-full text-muted transition #{hover}"
      end

      #: () -> untyped
      def confidence_percent
        return nil if @item.confidence_score.nil?

        (@item.confidence_score * 100).round
      end

      #: () -> untyped
      def rename_path
        move_box_review_rename_item_path(@move, @box, @media, @item)
      end

      #: () -> untyped
      def remove_path
        queue = @queue ? { queue: ReviewsController::QUEUE_PARAM } : {}
        move_box_review_remove_item_path(@move, @box, @media, @item, **queue)
      end
    end
  end
end
