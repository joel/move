# frozen_string_literal: true

module Views
  module Boxes
    # B1 — Box detail & lifecycle. Identity, room/status, dimensions + derived
    # volume + weight, and the action set (capture/add-item entries + lifecycle
    # transitions). Items inventory and the media gallery render as placeholders
    # until D5 (Items) and D4 (Media/recognition). Renders in the AppShellLayout.
    class Show < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      # Lifecycle target status => action label key (boxes.actions.*).
      ACTION_KEYS = {
        "sealed" => "seal", "packing" => "unseal", "in_transit" => "in_transit",
        "unpacking" => "unpacking", "unpacked" => "unpacked"
      }.freeze

      def initialize(move:, box:, items: [], media: [])
        @move = move
        @box = box
        @items = items
        @media = media
        @measurements = BoxMeasurements.new(box, unit_system: move.unit_system)
      end

      def view_template
        back_link
        header_bento
        detail_split
      end

      private

      def back_link
        a(
          href: move_boxes_path(@move),
          class: "inline-flex items-center gap-2 text-label-caps uppercase text-muted hover:text-text-warm"
        ) do
          render Components::Icons::ChevronRight.new(css: "h-4 w-4 rotate-180")
          plain I18n.t("boxes.show.back")
        end
      end

      def header_bento
        div(class: "grid grid-cols-1 gap-stack-gap md:grid-cols-3") do
          primary_card
          actions_card
        end
      end

      def primary_card
        render Components::Ui::Card.new(padding: "p-6", class: "md:col-span-2") do
          div(class: "flex items-start justify-between gap-3") do
            div(class: "flex flex-col gap-3") do
              h2(class: "text-headline-xl text-text-warm") { box_title }
              div(class: "flex flex-wrap gap-2") { chips }
            end
            edit_link if @move.writable?
          end
          measurements_row
        end
      end

      def chips
        if @box.room
          span(class: "inline-flex items-center rounded-full bg-accent-sage/15 px-3 py-1 " \
                      "text-label-caps uppercase text-accent-sage") { @box.room.name }
        end
        span(class: "inline-flex items-center gap-2 rounded-full bg-surface-container-high px-3 py-1 " \
                    "text-label-caps uppercase text-on-surface-variant") do
          span(class: "h-2 w-2 rounded-full bg-accent-sage")
          plain I18n.t("boxes.status.#{@box.status}")
        end
      end

      def edit_link
        a(
          href: edit_move_box_path(@move, @box),
          aria_label: I18n.t("boxes.show.edit"),
          class: "rounded-full p-2 text-muted transition hover:bg-surface-container-high hover:text-text-warm"
        ) { render Components::Icons::Pencil.new(css: "h-5 w-5") }
      end

      def measurements_row
        div(class: "mt-8 flex items-end justify-between") do
          div do
            p(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.show.dimensions") }
            p(class: "text-body-md text-text-warm") { @measurements.dimensions || "—" }
            p(class: "mt-1 text-sm text-muted") { I18n.t("boxes.show.volume", value: @measurements.volume) } if @measurements.volume
          end
          div(class: "text-right") do
            p(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.show.weight") }
            p(class: "text-headline-md text-text-warm") { @measurements.weight || "—" }
          end
        end
      end

      def actions_card
        render Components::Ui::Card.new(padding: "p-6") do
          div(class: "flex flex-col gap-3") do
            if @move.writable?
              capture_action
              add_item_action
              lifecycle_actions
            else
              p(class: "text-body-md text-muted") { I18n.t("boxes.show.read_only") }
            end
          end
        end
      end

      # Capture (D4) and manual add (D5) entries — present per the B1 design but
      # inert until those phases. Capture is blocked once the box is sealed.
      def capture_action
        return unless @box.capturable?

        render Components::Ui::Button.new(
          label: I18n.t("boxes.actions.capture"), icon: Components::Icons::Camera,
          full_width: true, href: move_box_capture_path(@move, @box)
        )
      end

      def add_item_action
        render Components::Ui::Button.new(
          label: I18n.t("boxes.actions.add_item"), variant: :secondary,
          full_width: true, disabled: true
        )
      end

      def lifecycle_actions
        @box.available_transitions.each do |target|
          button_to(
            I18n.t("boxes.actions.#{ACTION_KEYS.fetch(target)}"),
            transition_move_box_path(@move, @box),
            method: :patch,
            params: { to: target },
            class: transition_button_classes(target)
          )
        end
      end

      def transition_button_classes(target)
        base = "inline-flex w-full items-center justify-center rounded-full px-6 py-3 " \
               "text-sm font-bold transition active:scale-[0.98]"
        if target == "sealed"
          "#{base} bg-accent-sage text-page hover:opacity-90"
        else
          "#{base} border border-card-border text-text-warm hover:bg-surface-container-high"
        end
      end

      def detail_split
        div(class: "grid grid-cols-1 gap-stack-gap lg:grid-cols-12") do
          items_section
          gallery_section
        end
      end

      # Read-only inventory (item edit → D5, review actions → D6).
      def items_section
        section(class: "flex flex-col gap-stack-gap lg:col-span-8") do
          div(class: "flex items-center justify-between px-2") do
            h3(class: "text-headline-md text-text-warm") { I18n.t("boxes.show.items") }
            pending_badge if pending_count.positive?
          end
          @items.any? ? items_list : items_empty
        end
      end

      def pending_badge
        span(class: "rounded-full bg-tertiary/15 px-3 py-1 text-label-caps uppercase text-tertiary") do
          I18n.t("boxes.show.pending_review", count: pending_count)
        end
      end

      def items_list
        div(class: "flex flex-col divide-y divide-card-border rounded-card border border-card-border bg-card") do
          @items.each { |item| item_row(item) }
        end
      end

      def item_row(item)
        div(class: "flex items-center justify-between gap-3 p-4") do
          div(class: "flex flex-col gap-1") do
            span(class: "text-body-lg text-text-warm") { item_label(item) }
            span(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.item.fragile") } if item.fragile?
          end
          render Components::Ui::Chip.new(label: I18n.t("boxes.item_state.#{item.review_state}"), kind: item_chip_kind(item))
        end
      end

      def item_label(item)
        item.quantity > 1 ? "#{item.name} ×#{item.quantity}" : item.name
      end

      def item_chip_kind(item)
        item.review_state == "pending_review" ? :tag : :room
      end

      def items_empty
        render Components::Ui::EmptyState.new(
          title: I18n.t("boxes.show.items_empty_title"),
          description: I18n.t("boxes.show.items_empty_description")
        )
      end

      # Full-media gallery — never crops/bounding boxes (Domain §4.9, TF §13).
      def gallery_section
        aside(class: "flex flex-col gap-stack-gap lg:col-span-4") do
          div(class: "flex items-center justify-between px-2") do
            h3(class: "text-headline-md text-text-warm") { I18n.t("boxes.show.gallery") }
            span(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.show.photos", count: @media.size) }
          end
          @media.any? ? gallery_grid : gallery_empty
        end
      end

      def gallery_grid
        div(class: "grid grid-cols-2 gap-3") do
          @media.each { |media| gallery_thumb(media) }
        end
      end

      def gallery_thumb(media)
        div(class: "flex aspect-square items-center justify-center overflow-hidden " \
                   "rounded-xl bg-surface-container-high text-muted") do
          if media.image.attached?
            img(
              src: view_context.rails_storage_proxy_path(media.image),
              class: "h-full w-full object-cover", alt: "", loading: "lazy"
            )
          else
            render Components::Icons::Camera.new(css: "h-7 w-7")
          end
        end
      end

      def gallery_empty
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Camera,
          title: I18n.t("boxes.show.gallery_empty_title"),
          description: I18n.t("boxes.show.gallery_empty_description")
        )
      end

      def pending_count
        @items.count { |item| item.review_state == "pending_review" }
      end

      def box_title
        I18n.t("boxes.show.title", number: Kernel.format("%03d", @box.number.to_i))
      end
    end
  end
end
