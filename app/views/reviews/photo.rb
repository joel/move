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

      def initialize(move:, box:, media:, items:, position:, total:, next_media:, editable: false)
        @move = move
        @box = box
        @media = media
        @items = items
        @position = position
        @total = total
        @next_media = next_media
        @editable = editable
      end

      def view_template
        progress_bar
        div(class: "grid grid-cols-1 gap-stack-gap lg:grid-cols-12") do
          media_panel
          items_panel
        end
      end

      private

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

      def media_panel
        section(class: "lg:col-span-7") do
          div(class: "relative overflow-hidden rounded-card border border-card-border bg-surface-container-high") do
            badge
            if @media.image.attached?
              img(src: view_context.rails_storage_proxy_path(@media.image),
                  class: "aspect-square w-full object-cover lg:aspect-auto lg:h-full", alt: "", loading: "lazy")
            else
              div(class: "flex aspect-square w-full items-center justify-center text-muted") do
                render Components::Icons::Camera.new(css: "h-10 w-10")
              end
            end
          end
        end
      end

      def badge
        div(class: "absolute left-3 top-3 z-10 inline-flex items-center gap-2 rounded-full " \
                   "bg-surface-container-high/80 px-3 py-1 text-label-caps uppercase text-on-surface-variant " \
                   "backdrop-blur") do
          render Components::Icons::Camera.new(css: "h-3.5 w-3.5 text-accent-sage")
          plain I18n.t("reviews.photo.badge", position: @position, total: @total)
        end
      end

      def items_panel
        section(class: "lg:col-span-5") do
          render Components::Ui::Card.new(padding: "p-6") do
            header
            list
            add_form if @editable
            footer
          end
        end
      end

      def header
        h2(class: "text-headline-lg text-text-warm") { I18n.t("reviews.photo.title") }
        p(class: "mt-1 text-body-md text-muted") do
          I18n.t(@editable ? "reviews.photo.subtitle" : "reviews.photo.view_only")
        end
      end

      def list
        return empty_state if @items.empty?

        div(class: "mt-5 flex flex-col gap-stack-gap") do
          @items.each { |item| row(item) }
        end
      end

      def row(item)
        div(
          data: row_data(item),
          class: "group flex items-center gap-3 rounded-card border border-card-border bg-card p-4 " \
                 "transition focus-within:border-accent-sage"
        ) do
          div(class: "flex flex-1 flex-col gap-1") do
            name_field(item)
            confidence_line(item)
          end
          row_actions(item) if @editable
        end
      end

      def row_data(item)
        return {} unless @editable

        { controller: "inline-rename", inline_rename_url_value: rename_path(item) }
      end

      def name_field(item)
        input(
          type: "text", value: item.name, readonly: !@editable,
          aria_label: I18n.t("reviews.photo.name"), data: name_field_data,
          class: "w-full border-0 bg-transparent p-0 text-body-lg text-text-warm focus:ring-0"
        )
      end

      def name_field_data
        return {} unless @editable

        { inline_rename_target: "input",
          action: "focus->inline-rename#clearError blur->inline-rename#save keydown.enter->inline-rename#blur" }
      end

      def confidence_line(item)
        div(class: "flex items-center gap-1.5") do
          if (pct = confidence_percent(item))
            span(class: "h-1.5 w-1.5 rounded-full bg-accent-sage")
            span(class: "text-label-caps uppercase text-muted") do
              I18n.t("reviews.photo.confidence", percent: pct)
            end
          else
            span(class: "text-label-caps uppercase text-muted") { I18n.t("reviews.photo.added") }
          end
        end
      end

      def row_actions(item)
        div(class: "flex shrink-0 items-center gap-1") do
          button(type: "button", data: { action: "inline-rename#focus" }, class: icon_button(:sage)) do
            render Components::Icons::Pencil.new(css: "h-5 w-5")
            span(class: "sr-only") { I18n.t("reviews.photo.edit") }
          end
          button_to(
            move_box_review_remove_item_path(@move, @box, @media, item),
            method: :patch, class: icon_button(:error), form_class: "shrink-0"
          ) do
            render Components::Icons::Close.new(css: "h-5 w-5")
            span(class: "sr-only") { I18n.t("reviews.photo.remove_named", name: item.name) }
          end
        end
      end

      # An inline "add a missed item" row: type a name, submit to append it to this
      # photo. Server-side create keeps it robust (no client-only rows to lose).
      def add_form
        form_with(url: move_box_review_add_item_path(@move, @box, @media), method: :post,
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
      def advance_link(key, href)
        a(href: href, data: { turbo_prefetch: "false" },
          class: "inline-flex w-full items-center justify-center gap-2 rounded-full bg-accent-sage " \
                 "px-6 py-3 text-sm font-bold text-page transition hover:opacity-90 active:scale-[0.98]") do
          plain I18n.t(key)
          render Components::Icons::ChevronRight.new(css: "h-4 w-4")
        end
      end

      def empty_state
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Camera,
          title: I18n.t("reviews.photo.empty_title"),
          description: I18n.t("reviews.photo.empty_description")
        )
      end

      def icon_button(tint)
        hover = tint == :error ? "hover:text-error hover:bg-error/10" : "hover:text-accent-sage hover:bg-accent-sage/10"
        "flex h-10 w-10 items-center justify-center rounded-full text-muted transition #{hover}"
      end

      def confidence_percent(item)
        return nil if item.confidence_score.nil?

        (item.confidence_score * 100).round
      end

      def rename_path(item)
        move_box_review_rename_item_path(@move, @box, @media, item)
      end

      def progress_pct
        return 0 if @total.zero?

        ((@position.to_f / @total) * 100).round
      end
    end
  end
end
