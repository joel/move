# frozen_string_literal: true

module Components
  module Boxes
    # B1 — the "Manage box" overflow. A ⋮ trigger plus a native-<dialog> bottom
    # sheet (.ha-sheet) holding the box's *secondary* actions, so the box detail
    # surfaces a single contextual hero (Capture / Open unpacking / forward
    # transition) while everything else — the remaining lifecycle step(s), the two
    # print actions, Edit and Delete — lives one tap away here.
    #
    # `consumed` is the lifecycle target the header already promoted to its hero
    # (e.g. `in_transit` for a sealed box); the sheet lists the rest so a forward
    # step is never offered twice. Reuses the modal Stimulus controller; Seal keeps
    # its describe-before-sealing dialog (rendered as a row via BoxSealTrigger).
    class ManageSheet < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      ROW = "flex w-full items-center gap-4 rounded-lg bg-surface-container-high p-4 " \
            "text-left text-body-md font-semibold text-text-warm transition " \
            "hover:bg-surface-container-highest active:scale-[0.98]"
      DANGER_ROW = "flex w-full items-center gap-4 rounded-lg bg-surface-container-high p-4 " \
                   "text-left text-body-md font-semibold text-error transition " \
                   "hover:bg-error/10 active:scale-[0.98]"

      #: (move: untyped, box: untyped, ?editable: untyped, ?consumed: untyped, ?omit_delete: untyped) -> void
      def initialize(move:, box:, editable: false, consumed: nil, omit_delete: false)
        @move = move
        @box = box
        @editable = editable
        @consumed = consumed
        # The header promotes Delete to the hero for an unpacked box, so the sheet
        # omits its row to avoid offering Delete twice.
        @omit_delete = omit_delete
      end

      #: () -> void
      def view_template
        div(data: { controller: "modal" }) do
          trigger
          dialog(
            class: "ha-sheet",
            data: { modal_target: "dialog", action: "click->modal#backdropClose" }
          ) { sheet_body }
        end
      end

      private

      #: () -> untyped
      def trigger
        button(
          type: "button", data: { action: "modal#open" },
          aria_label: I18n.t("boxes.manage.trigger"),
          class: "rounded-full p-2 text-muted transition hover:bg-surface-container-high " \
                 "hover:text-text-warm"
        ) { render Components::Icons::EllipsisVertical.new(css: "h-5 w-5") }
      end

      #: () -> untyped
      def sheet_body
        div(class: "w-12 h-1.5 rounded-full bg-outline-variant/60 mx-auto mb-4")
        h3(class: "text-headline-md text-text-warm mb-4") do
          I18n.t("boxes.manage.title", number: Kernel.format("%03d", @box.number.to_i))
        end
        details_block
        div(class: "flex flex-col gap-2") do
          lifecycle_rows if @editable
          print_rows
          edit_row if @editable
          delete_section if @editable && !@omit_delete
        end
      end

      # Read-only dimensions + weight — demoted off the slim box header (#401), they
      # surface here (and on the Edit form, where they're set).

      #: () -> untyped
      def details_block
        measurements = BoxMeasurements.new(@box, unit_system: @move.unit_system)
        div(class: "mb-4 flex items-center justify-between rounded-lg bg-surface-container-high px-4 py-3") do
          div do
            p(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.show.dimensions") }
            p(class: "text-body-md text-text-warm") { measurements.dimensions || "—" }
            volume_line(measurements.volume)
          end
          div(class: "text-right") do
            p(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.show.weight") }
            p(class: "text-body-md text-text-warm") { measurements.weight || "—" }
          end
        end
      end

      #: (untyped volume) -> untyped
      def volume_line(volume)
        return unless volume

        p(class: "text-sm text-muted") { I18n.t("boxes.show.volume", value: volume) }
      end

      # The lifecycle transitions still available from here, minus the one the
      # header already shows as the hero (so a forward step isn't offered twice).

      #: () -> untyped
      def lifecycle_rows
        (@box.available_transitions - [@consumed]).each do |target|
          if target == "sealed" && seal_needs_description?
            render Components::BoxSealTrigger.new(
              move: @move, box: @box, trigger_class: ROW, trigger_icon: Components::Icons::Lock
            )
          else
            transition_row(target)
          end
        end
      end

      #: (untyped target) -> untyped
      def transition_row(target)
        button_to(
          transition_move_box_path(@move, @box),
          method: :patch, params: { to: target }, class: ROW, form_class: "w-full"
        ) do
          render transition_icon(target).new(css: "h-5 w-5")
          span { transition_label(target) }
        end
      end

      #: () -> untyped
      def print_rows
        link_row(I18n.t("boxes.actions.print_label"), Components::Icons::Printer,
                 move_box_label_path(@move, @box))
        link_row(I18n.t("boxes.actions.print_manifest"), Components::Icons::Printer,
                 move_box_manifest_path(@move, @box))
      end

      #: () -> untyped
      def edit_row
        link_row(I18n.t("boxes.actions.edit"), Components::Icons::Pencil,
                 edit_move_box_path(@move, @box), turbo: true)
      end

      #: () -> untyped
      def delete_section
        div(class: "mt-1 border-t border-card-border pt-2") do
          button_to(
            move_box_path(@move, @box),
            method: :delete, class: DANGER_ROW, form_class: "w-full",
            data: { turbo_confirm: I18n.t("boxes.actions.delete_confirm") }
          ) do
            render Components::Icons::Trash.new(css: "h-5 w-5")
            span { I18n.t("boxes.actions.delete") }
          end
        end
      end

      # A link row. Print targets open the inline PDF in a new tab; Edit is a
      # same-tab navigation (Turbo-driven).

      #: (untyped label, untyped icon, untyped href, ?turbo: untyped) -> untyped
      def link_row(label, icon, href, turbo: false)
        attrs = turbo ? {} : { target: "_blank", rel: "noopener" }
        a(href: href, class: ROW, **attrs) do
          render icon.new(css: "h-5 w-5")
          span { label }
        end
      end

      #: () -> untyped
      def seal_needs_description?
        @box.room_id.present? && @box.description.blank? && @box.item_count.positive?
      end

      #: (untyped target) -> untyped
      def transition_label(target)
        case target
        when "sealed" then I18n.t("boxes.actions.seal")
        when "packing" then I18n.t("boxes.actions.unseal")
        when "in_transit" then I18n.t("boxes.actions.in_transit")
        when "unpacked" then I18n.t("boxes.actions.unpacked")
        when "unpacking" then I18n.t("boxes.actions.reopen")
        end
      end

      #: (untyped target) -> untyped
      def transition_icon(target)
        case target
        when "sealed" then Components::Icons::Lock
        when "unpacked" then Components::Icons::Check
        else Components::Icons::Swap
        end
      end
    end
  end
end
