# frozen_string_literal: true

module Components
  module Boxes
    # B1 — the box-detail header. A *plain-text* identity (chips, number, contents
    # subtitle) on the page background — no card, no shadow — with a quick-edit
    # pencil + the ⋮ Manage-box sheet, sitting ABOVE a prominent contextual hero
    # (Capture / Open unpacking / the forward lifecycle step) with a quiet
    # "Add manually" link. The box is deliberately uncluttered so the hero —
    # Capture — is the page's focal action, not a feature of a dominant box card
    # (Stitch "Approach 1"). Dimensions and weight live in the Manage sheet;
    # everything secondary lives in Components::Boxes::ManageSheet.
    #
    # Stable id so BoxesController#transition can Turbo-replace the whole region
    # after a lifecycle change — the status chip, the hero action and the sheet's
    # available transitions all shift with status — without reloading the page.
    class HeaderBento < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      ID = "box-header-bento"

      # The prominent, full-width hero pill — the page's primary action. Sage for
      # the positive task/lifecycle action; error for the terminal Delete (an
      # unpacked box is done — the coherent next step is to remove it).
      HERO_LAYOUT = "w-full inline-flex items-center justify-center gap-3 rounded-full " \
                    "px-6 py-5 text-headline-md font-bold transition hover:opacity-90 " \
                    "active:scale-[0.98]"
      HERO_CLASS = "#{HERO_LAYOUT} bg-accent-sage text-page".freeze
      HERO_DANGER_CLASS = "#{HERO_LAYOUT} bg-error text-on-error".freeze

      #: (move: untyped, box: untyped, ?editable: untyped) -> void
      def initialize(move:, box:, editable: false)
        @move = move
        @box = box
        @editable = editable
      end

      #: () -> void
      def view_template
        div(id: ID, class: "flex flex-col gap-6") do
          identity
          hero_zone
        end
      end

      private

      # Plain-text identity on the page background (no card / shadow): chips →
      # number → contents subtitle, with the quick-edit pencil + ⋮ Manage sheet
      # aligned top-right.

      #: () -> untyped
      def identity
        div(class: "flex items-start justify-between gap-3") do
          div(class: "flex flex-col gap-2") do
            div(class: "flex flex-wrap gap-2") { chips }
            h2(class: "text-headline-lg text-text-warm") { box_title }
            subtitle
          end
          header_actions
        end
      end

      # Quick-edit pencil (editor) + the ⋮ Manage-box sheet (always — it carries the
      # box dimensions and the print actions even for a viewer / archived Move).

      #: () -> untyped
      def header_actions
        div(class: "flex shrink-0 items-center gap-1") do
          edit_link if @editable
          render Components::Boxes::ManageSheet.new(
            move: @move, box: @box, editable: @editable,
            consumed: consumed_transition, omit_delete: hero == :delete
          )
        end
      end

      # Contents description as a one-line subtitle; when blank, a quiet
      # "add a description" link to the edit form (where the ✨ AI-suggest lives),
      # for an editable Move only.

      #: () -> untyped
      def subtitle
        if @box.description.present?
          p(class: "text-body-md text-on-surface-variant") { @box.description }
        elsif @editable
          a(
            href: edit_move_box_path(@move, @box),
            class: "inline-flex items-center gap-1.5 text-body-md text-accent-sage transition hover:opacity-80"
          ) do
            render Components::Icons::Sparkles.new(css: "h-[18px] w-[18px]")
            plain I18n.t("boxes.show.add_description")
          end
        end
      end

      #: () -> untyped
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
        # Manual fragile mark (Phase A) — terracotta, the design system's Fragile
        # tint (DESIGN.md), matching the FRAGILE mark printed on the box label.
        render Components::Ui::Chip.new(label: I18n.t("boxes.fragile_badge"), kind: :tag) if @box.fragile?
      end

      #: () -> untyped
      def edit_link
        a(
          href: edit_move_box_path(@move, @box),
          aria_label: I18n.t("boxes.show.edit"),
          class: "rounded-full p-2 text-muted transition hover:bg-surface-container-high hover:text-text-warm"
        ) { render Components::Icons::Pencil.new(css: "h-5 w-5") }
      end

      # The single contextual primary action for the box's phase, made prominent —
      # with a quiet "Add manually" beneath it (Stitch "Approach 1"). A read-only
      # Move shows the quiet read-only note instead (and, where applicable, the
      # unpacking entry — that surface is open to viewers).

      #: () -> untyped
      def hero_zone
        div(class: "flex flex-col items-center gap-2") do
          case hero
          when :unpack then unpack_action
          when :capture then capture_action
          when :transition then forward_transition_action
          when :delete then delete_action
          end
          # Manual add only makes sense while the box is open (packing) — same gate
          # as Capture; a sealed / in-transit / unpacking box must not offer it.
          add_manually_link if hero == :capture
          read_only_note unless @editable
        end
      end

      # Hero precedence: the destination-side checklist and capture are the rich
      # phase *tasks*; for the "holding" states (sealed / in_transit) the forward
      # lifecycle step is promoted so the zone is never empty. An *unpacked* box is
      # done — its coherent next action is to delete it (an editor); a viewer still
      # gets the read-only checklist view. Backward steps (Unseal / Reopen) and
      # utilities always live in the Manage-box sheet.

      #: () -> untyped
      def hero
        return @hero if defined?(@hero)

        @hero =
          if @box.unpacked? && @editable then :delete
          elsif @box.unpacking? || @box.unpacked? then :unpack
          elsif @editable then editable_hero
          end
      end

      # The hero for an editable, non-destination box: capture while packing, else
      # the forward lifecycle step (sealed → in_transit, in_transit → unpacking).

      #: () -> untyped
      def editable_hero
        return :capture if @box.capturable?

        :transition if forward_transition
      end

      # The forward lifecycle target promoted to the hero for a holding state.

      #: () -> untyped
      def forward_transition
        case @box.status
        when "sealed" then "in_transit"
        when "in_transit" then "unpacking"
        end
      end

      # The lifecycle target the hero consumes, so ManageSheet omits it (only the
      # forward-transition hero consumes one; capture/unpack leave Seal/Mark-unpacked
      # in the sheet).

      #: () -> untyped
      def consumed_transition
        forward_transition if hero == :transition
      end

      #: () -> untyped
      def unpack_action
        a(href: move_box_unpacking_path(@move, @box), class: HERO_CLASS) do
          render Components::Icons::Boxes.new(css: "h-6 w-6")
          span { I18n.t("boxes.actions.unpack") }
        end
      end

      #: () -> untyped
      def capture_action
        a(href: move_box_capture_path(@move, @box), class: HERO_CLASS) do
          render Components::Icons::Camera.new(css: "h-6 w-6")
          span { I18n.t("boxes.actions.capture") }
        end
      end

      #: () -> untyped
      def forward_transition_action
        target = forward_transition
        button_to(
          transition_move_box_path(@move, @box),
          method: :patch, params: { to: target }, form_class: "w-full", class: HERO_CLASS
        ) { span { I18n.t("boxes.actions.#{target}") } }
      end

      # Terminal action for an unpacked box: the prominent (but danger-styled +
      # confirmed) Delete. Mirrors the sheet's delete; ManageSheet omits its row
      # here so Delete isn't offered twice.

      #: () -> untyped
      def delete_action
        button_to(
          move_box_path(@move, @box),
          method: :delete, form_class: "w-full", class: HERO_DANGER_CLASS,
          data: { turbo_confirm: I18n.t("boxes.actions.delete_confirm") }
        ) do
          render Components::Icons::Trash.new(css: "h-6 w-6")
          span { I18n.t("boxes.actions.delete") }
        end
      end

      # Quiet secondary action under the hero — the "Subtle Add" half of Approach 1.

      #: () -> untyped
      def add_manually_link
        a(
          href: new_move_box_item_path(@move, @box),
          class: "text-body-md text-muted transition hover:text-text-warm"
        ) { I18n.t("boxes.actions.add_manually") }
      end

      #: () -> untyped
      def read_only_note
        p(class: "text-body-md text-muted text-center") do
          I18n.t(@move.archived? ? "boxes.show.archived" : "boxes.show.view_only")
        end
      end

      #: () -> untyped
      def box_title
        I18n.t("boxes.show.title", number: Kernel.format("%03d", @box.number.to_i))
      end
    end
  end
end
