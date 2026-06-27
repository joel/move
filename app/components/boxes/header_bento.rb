# frozen_string_literal: true

module Components
  module Boxes
    # B1 — the box-detail header: a primary card (identity, room/status chips,
    # dimensions, contents description) and an actions card (capture / add-item /
    # lifecycle transitions / print). Stable id so BoxesController#transition can
    # Turbo-replace the whole region after a lifecycle change — the status chip,
    # the available action buttons, capture/unpacking visibility and the contents
    # description all shift with status — without reloading the page.
    class HeaderBento < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      ID = "box-header-bento"

      # Lifecycle target status => action label key (boxes.actions.*).
      ACTION_KEYS = {
        "sealed" => "seal", "packing" => "unseal", "in_transit" => "in_transit",
        "unpacking" => "unpacking", "unpacked" => "unpacked"
      }.freeze

      def initialize(move:, box:, editable: false)
        @move = move
        @box = box
        @editable = editable
        @measurements = BoxMeasurements.new(box, unit_system: move.unit_system)
      end

      def view_template
        div(id: ID, class: "grid grid-cols-1 gap-stack-gap md:grid-cols-3") do
          primary_card
          actions_card
        end
      end

      private

      def primary_card
        render Components::Ui::Card.new(padding: "p-6", class: "md:col-span-2") do
          div(class: "flex items-start justify-between gap-3") do
            div(class: "flex flex-col gap-3") do
              h2(class: "text-headline-xl text-text-warm") { box_title }
              div(class: "flex flex-wrap gap-2") { chips }
            end
            edit_link if @editable
          end
          measurements_row
          contents_row
        end
      end

      # Contents description (B1). Shown as a sage-tinted panel when present;
      # otherwise a quiet "add a description" link to the edit form (where the ✨
      # AI-suggest lives), for an editable Move only.
      def contents_row
        if @box.description.present?
          div(class: "mt-4 rounded-xl border border-accent-sage/20 bg-accent-sage/5 p-4") do
            div(class: "mb-2 flex items-center gap-2") do
              render Components::Icons::Sparkles.new(css: "h-[18px] w-[18px] text-accent-sage")
              span(class: "text-label-caps uppercase text-accent-sage") { I18n.t("boxes.show.contents") }
            end
            p(class: "text-body-md leading-relaxed text-on-surface-variant") { @box.description }
          end
        elsif @editable
          a(
            href: edit_move_box_path(@move, @box),
            class: "mt-4 inline-flex items-center gap-1.5 text-body-md text-accent-sage transition hover:opacity-80"
          ) do
            render Components::Icons::Sparkles.new(css: "h-[18px] w-[18px]")
            plain I18n.t("boxes.show.add_description")
          end
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
            unpacking_action
            if @editable
              capture_action
              add_item_action
              lifecycle_actions
            else
              p(class: "text-body-md text-muted") do
                I18n.t(@move.archived? ? "boxes.show.archived" : "boxes.show.view_only")
              end
            end
            print_actions
          end
        end
      end

      def unpacking_action
        return unless @box.unpacking? || @box.unpacked?

        render Components::Ui::Button.new(
          label: I18n.t("boxes.actions.unpack"), icon: Components::Icons::Boxes,
          full_width: true, href: move_box_unpacking_path(@move, @box)
        )
      end

      def print_actions
        render Components::Ui::Button.new(
          label: I18n.t("boxes.actions.print_label"), variant: :secondary, full_width: true,
          href: move_box_label_path(@move, @box), target: "_blank", rel: "noopener"
        )
        render Components::Ui::Button.new(
          label: I18n.t("boxes.actions.print_manifest"), variant: :ghost, full_width: true,
          href: move_box_manifest_path(@move, @box), target: "_blank", rel: "noopener"
        )
      end

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
          full_width: true, href: new_move_box_item_path(@move, @box)
        )
      end

      def lifecycle_actions
        @box.available_transitions.each do |target|
          if target == "sealed" && seal_needs_description?
            render Components::BoxSealTrigger.new(move: @move, box: @box)
          else
            button_to(
              I18n.t("boxes.actions.#{ACTION_KEYS.fetch(target)}"),
              transition_move_box_path(@move, @box),
              method: :patch, params: { to: target },
              class: transition_button_classes(target)
            )
          end
        end
      end

      # Intercept the seal with the describe-before-sealing modal only when the seal
      # can actually succeed (a room is assigned) and there's something to describe
      # with no description yet. Otherwise sealing stays a one-click button_to.
      def seal_needs_description?
        @box.room_id.present? && @box.description.blank? && @box.item_count.positive?
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

      def box_title
        I18n.t("boxes.show.title", number: Kernel.format("%03d", @box.number.to_i))
      end
    end
  end
end
