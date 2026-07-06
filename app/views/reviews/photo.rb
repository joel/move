# frozen_string_literal: true

module Views
  module Reviews
    # C2 — Review by photo. One photo per screen: the image once on the left, and
    # every item detected in it on the right as an editable field (rename auto-saves
    # on blur), each with a pencil (focus + select-all) and × (remove). "+ Add item"
    # appends a missed item; "Next Photo" only navigates. Renders in AppShellLayout.
    class Photo < Views::Base
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::FormWith

      # @rbs move: untyped
      # @rbs box: untyped
      # @rbs media: untyped
      # @rbs items: untyped
      # @rbs position: untyped
      # @rbs total: untyped
      # @rbs next_media: untyped
      # @rbs editable: untyped
      # @rbs move_boxes: untyped
      # @rbs return: void
      def initialize(move:, box:, media:, items:, position:, total:, next_media:, editable: false, move_boxes: [])
        @move = move
        @box = box
        @media = media
        @items = items
        @position = position
        @total = total
        @next_media = next_media
        @editable = editable
        # Other boxes in this Move the photo can be moved to (#317); empty when this
        # is the only box (the control is then hidden).
        @move_boxes = move_boxes
      end

      #: () -> void
      def view_template
        progress_bar
        div(class: "grid grid-cols-1 gap-stack-gap lg:grid-cols-12") do
          media_panel
          items_panel
        end
      end

      private

      #: () -> untyped
      def progress_bar
        div(class: "flex items-center gap-4") do
          a(href: move_box_path(@move, @box),
            class: "flex h-10 w-10 items-center justify-center rounded-full bg-card text-muted hover:text-text-warm") do
            render Components::Icons::ChevronRight.new(css: "h-5 w-5 rotate-180")
          end
          div(class: "flex flex-1 flex-col gap-1") do
            span(class: "text-label-caps uppercase text-muted") do
              I18n.t("reviews.photo.progress", position: @position, total: @total)
            end
            div(class: "h-1.5 w-full overflow-hidden rounded-full bg-surface-container-high") do
              div(class: "h-full rounded-full bg-accent-sage", style: "width: #{progress_pct}%")
            end
          end
        end
      end

      #: () -> untyped
      def media_panel
        section(class: "lg:col-span-7") do
          div(class: "relative overflow-hidden rounded-card border border-card-border bg-surface-container-high") do
            badge
            if @media.image_displayable?
              img(src: MediaVariants::TransformUrl.for(@media, :detail),
                  class: "aspect-square w-full object-cover lg:aspect-auto lg:h-full", alt: "", loading: "lazy")
            elsif @media.image_unavailable?
              div(class: "flex aspect-square w-full flex-col items-center justify-center gap-2 text-muted") do
                render Components::Icons::ImageOff.new(css: "h-10 w-10")
                span(class: "text-body-md") { I18n.t("ui.media.unavailable") }
              end
            else
              div(class: "flex aspect-square w-full items-center justify-center text-muted") do
                render Components::Icons::Camera.new(css: "h-10 w-10")
              end
            end
          end
        end
      end

      #: () -> untyped
      def badge
        div(class: "absolute left-3 top-3 z-10 inline-flex items-center gap-2 rounded-full " \
                   "bg-surface-container-high/80 px-3 py-1 text-label-caps uppercase text-on-surface-variant " \
                   "backdrop-blur") do
          render Components::Icons::Camera.new(css: "h-3.5 w-3.5 text-accent-sage")
          plain I18n.t("reviews.photo.badge", position: @position, total: @total)
        end
      end

      #: () -> untyped
      def items_panel
        section(class: "lg:col-span-5") do
          render Components::Ui::Card.new(padding: "p-6") do
            header
            list
            add_form if @editable
            move_photo_control if @editable && @move_boxes.any?
            retake_control if @editable
            delete_photo_control if @editable && @box.packing?
            footer
          end
        end
      end

      #: () -> untyped
      def header
        h2(class: "text-headline-lg text-text-warm") { I18n.t("reviews.photo.title") }
        p(class: "mt-1 text-body-md text-muted") do
          I18n.t(@editable ? "reviews.photo.subtitle" : "reviews.photo.view_only")
        end
      end

      #: () -> untyped
      def list
        render Components::Reviews::ItemList.new(
          move: @move, box: @box, media: @media, items: @items, editable: @editable
        )
      end

      # An inline "add a missed item" row: type a name, submit to append it to this
      # photo. Server-side create keeps it robust (no client-only rows to lose).

      #: () -> untyped
      def add_form
        form_with(url: move_box_review_add_item_path(@move, @box, @media), method: :post,
                  data: { controller: "reset-form", action: "turbo:submit-end->reset-form#reset" },
                  class: "mt-stack-gap flex items-center gap-2 rounded-card border border-dashed " \
                         "border-card-border bg-card p-2 focus-within:border-accent-sage") do
          span(class: "pl-2 text-muted") { render Components::Icons::Plus.new(css: "h-5 w-5") }
          input(type: "text", name: "item[name]", required: true,
                placeholder: I18n.t("reviews.photo.add_placeholder"),
                class: "w-full border-0 bg-transparent p-0 text-body-md text-text-warm focus:ring-0")
          button(type: "submit", class: icon_button(:sage)) do
            render Components::Icons::Check.new(css: "h-5 w-5")
            span(class: "sr-only") { I18n.t("reviews.photo.add") }
          end
        end
      end

      # Move the whole photo (and its co-located items) to another box (#317). A box
      # picker + submit; the server validates same-box / cross-move / archived.

      #: () -> untyped
      def move_photo_control
        div(class: "mt-stack-gap border-t border-card-border pt-stack-gap") do
          span(class: "text-label-caps uppercase text-muted") { I18n.t("reviews.photo.move_heading") }
          form_with(url: move_box_review_move_photo_path(@move, @box, @media), method: :patch,
                    class: "mt-2 flex items-center gap-2") do
            select(
              name: "target_box_id", aria_label: I18n.t("reviews.photo.move_heading"),
              class: "flex-1 rounded-card border border-card-border bg-card p-2 text-body-md " \
                     "text-text-warm focus:border-accent-sage focus:ring-0"
            ) do
              @move_boxes.each do |box|
                option(value: box.id) { I18n.t("reviews.photo.move_to_box", number: box.number) }
              end
            end
            render Components::Ui::Button.new(
              label: I18n.t("reviews.photo.move_submit"), type: "submit", variant: :secondary
            )
          end
        end
      end

      # Replace this photo's image in place (Captures::Retake) — recover a corrupt
      # master or swap a bad shot. Any phase. The tappable button is a label around a
      # hidden file input (camera on mobile); picking a photo auto-downscales
      # (capture-upload) and submits. The auto-submit action is on the FILE input, not
      # the form, so toggling the re-scan checkbox doesn't submit an empty upload.

      #: () -> untyped
      def retake_control
        div(class: "mt-stack-gap border-t border-card-border pt-stack-gap") do
          span(class: "text-label-caps uppercase text-muted") { I18n.t("reviews.photo.retake_heading") }
          form_with(url: move_box_review_retake_photo_path(@move, @box, @media), method: :post,
                    data: { controller: "capture-upload" }, class: "mt-2 flex flex-col gap-3") do |form|
            # Re-scan adds items, so it's only offered while the box can capture
            # (packing) — the action rejects it otherwise. A plain image swap stays
            # available in any phase.
            if @box.capturable?
              label(class: "flex items-center gap-2 text-body-md text-muted") do
                input(type: "checkbox", name: "rerun_recognition", value: "1",
                      class: "h-4 w-4 rounded border-card-border text-accent-sage focus:ring-accent-sage")
                plain I18n.t("reviews.photo.retake_rescan")
              end
            end
            label(class: "inline-flex w-full cursor-pointer items-center justify-center gap-2 rounded-full " \
                         "border border-card-border bg-card px-5 py-2 text-sm font-bold text-text-warm " \
                         "transition hover:border-accent-sage hover:text-accent-sage active:scale-[0.98]") do
              render Components::Icons::Camera.new(css: "h-5 w-5")
              plain I18n.t("reviews.photo.retake_submit")
              form.file_field :file, accept: "image/*", capture: "environment", required: true, class: "sr-only",
                                     data: { "capture-upload-target": "file", action: "change->capture-upload#submit" }
            end
          end
        end
      end

      # Delete this photo and every item it sourced (Photos::Delete) — packing only,
      # soft + restorable from the activity feed. A confirm guards the cascade.

      #: () -> untyped
      def delete_photo_control
        div(class: "mt-stack-gap border-t border-card-border pt-stack-gap") do
          span(class: "text-label-caps uppercase text-muted") { I18n.t("reviews.photo.delete_heading") }
          danger_classes = "inline-flex w-full items-center justify-center gap-2 rounded-full bg-error " \
                           "px-5 py-2 text-sm font-bold text-on-error transition hover:opacity-90 active:scale-[0.98]"
          button_to(move_box_review_photo_path(@move, @box, @media), method: :delete, form_class: "mt-2",
                                                                     class: danger_classes,
                                                                     data: { turbo_confirm: I18n.t("reviews.photo.delete_confirm") }) do
            render Components::Icons::Trash.new(css: "h-5 w-5")
            plain I18n.t("reviews.photo.delete_submit")
          end
        end
      end

      #: () -> untyped
      def footer
        div(class: "mt-6") do
          if @next_media
            advance_link("reviews.photo.next", move_box_review_photo_path(@move, @box, @next_media))
          else
            advance_link("reviews.photo.finish", move_box_path(@move, @box))
          end
        end
      end

      # Turbo prefetch is disabled: opening the next photo marks its items reviewed
      # (a GET-side effect), so hover-prefetching "Next Photo" must not confirm them
      # before the reviewer actually advances.

      #: (untyped key, untyped href) -> untyped
      def advance_link(key, href)
        a(href: href, data: { turbo_prefetch: "false" },
          class: "inline-flex w-full items-center justify-center gap-2 rounded-full bg-accent-sage " \
                 "px-6 py-3 text-sm font-bold text-page transition hover:opacity-90 active:scale-[0.98]") do
          plain I18n.t(key)
          render Components::Icons::ChevronRight.new(css: "h-4 w-4")
        end
      end

      # The add-form's submit button shares the row icon-button styling.

      #: (Symbol tint) -> String
      def icon_button(tint)
        hover = tint == :error ? "hover:text-error hover:bg-error/10" : "hover:text-accent-sage hover:bg-accent-sage/10"
        "flex h-10 w-10 items-center justify-center rounded-full text-muted transition #{hover}"
      end

      #: () -> Integer
      def progress_pct
        return 0 if @total.zero?

        ((@position.to_f / @total) * 100).round
      end
    end
  end
end
