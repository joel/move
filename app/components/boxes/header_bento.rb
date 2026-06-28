# frozen_string_literal: true

module Components
  module Boxes
    # B1 — the box-detail header: an identity card (number, room/status chips,
    # dimensions, contents) carrying a quick-edit pencil and the ⋮ Manage-box
    # sheet, over a single contextual hero action (Capture / Open unpacking / the
    # forward lifecycle step). Everything secondary lives in Components::Boxes::
    # ManageSheet — so the screen presents one clear thing to do per phase instead
    # of a stack of competing buttons (#398).
    #
    # Stable id so BoxesController#transition can Turbo-replace the whole region
    # after a lifecycle change — the status chip, the hero action and the sheet's
    # available transitions all shift with status — without reloading the page.
    class HeaderBento < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      ID = "box-header-bento"

      def initialize(move:, box:, editable: false)
        @move = move
        @box = box
        @editable = editable
        @measurements = BoxMeasurements.new(box, unit_system: move.unit_system)
      end

      def view_template
        div(id: ID, class: "flex flex-col gap-stack-gap") do
          primary_card
          hero_zone
        end
      end

      private

      def primary_card
        render Components::Ui::Card.new(padding: "p-6") do
          div(class: "flex items-start justify-between gap-3") do
            div(class: "flex flex-col gap-3") do
              h2(class: "text-headline-xl text-text-warm") { box_title }
              div(class: "flex flex-wrap gap-2") { chips }
            end
            header_actions
          end
          measurements_row
          contents_row
        end
      end

      # Quick-edit pencil (editor) + the ⋮ Manage-box sheet (always — it carries
      # the print actions even for a viewer / archived Move).
      def header_actions
        div(class: "flex items-center gap-1") do
          edit_link if @editable
          render Components::Boxes::ManageSheet.new(
            move: @move, box: @box, editable: @editable, consumed: consumed_transition
          )
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

      # The single contextual primary action for the box's phase. A read-only Move
      # shows the quiet read-only note instead (and, when applicable, the unpacking
      # entry — that surface is open to viewers).
      def hero_zone
        div(class: "flex flex-col items-center gap-2") do
          case hero
          when :unpack then unpack_action
          when :capture then capture_action
          when :transition then forward_transition_action
          end
          capture_hint if hero == :capture
          read_only_note unless @editable
        end
      end

      # Hero precedence: the destination-side checklist and capture are the rich
      # phase *tasks*; for the "holding" states (sealed / in_transit) the forward
      # lifecycle step is promoted so the zone is never empty. Backward steps
      # (Unseal / Reopen) and utilities always live in the Manage-box sheet.
      def hero
        return @hero if defined?(@hero)

        @hero =
          if @box.unpacking? || @box.unpacked? then :unpack
          elsif !@editable then nil
          elsif @box.capturable? then :capture
          elsif forward_transition then :transition
          end
      end

      # The forward lifecycle target promoted to the hero for a holding state.
      def forward_transition
        case @box.status
        when "sealed" then "in_transit"
        when "in_transit" then "unpacking"
        end
      end

      # The lifecycle target the hero consumes, so ManageSheet omits it (only the
      # forward-transition hero consumes one; capture/unpack leave Seal/Mark-unpacked
      # in the sheet).
      def consumed_transition
        forward_transition if hero == :transition
      end

      def unpack_action
        render Components::Ui::Button.new(
          label: I18n.t("boxes.actions.unpack"), icon: Components::Icons::Boxes,
          full_width: true, href: move_box_unpacking_path(@move, @box)
        )
      end

      def capture_action
        render Components::Ui::Button.new(
          label: I18n.t("boxes.actions.capture"), icon: Components::Icons::Camera,
          full_width: true, href: move_box_capture_path(@move, @box)
        )
      end

      def capture_hint
        p(class: "text-body-md text-on-surface-variant text-center opacity-80") do
          I18n.t("boxes.actions.capture_hint")
        end
      end

      def forward_transition_action
        target = forward_transition
        button_to(
          transition_move_box_path(@move, @box),
          method: :patch, params: { to: target }, form_class: "w-full",
          class: "inline-flex w-full items-center justify-center gap-2 rounded-full bg-accent-sage " \
                 "px-6 py-3 text-sm font-bold text-page transition hover:opacity-90 active:scale-[0.98]"
        ) { span { I18n.t("boxes.actions.#{target}") } }
      end

      def read_only_note
        p(class: "text-body-md text-muted text-center") do
          I18n.t(@move.archived? ? "boxes.show.archived" : "boxes.show.view_only")
        end
      end

      def box_title
        I18n.t("boxes.show.title", number: Kernel.format("%03d", @box.number.to_i))
      end
    end
  end
end
