# frozen_string_literal: true

module Components
  module Boxes
    # B1 — the box-detail header. A *lightweight* identity card (chips, number,
    # contents subtitle) with a quick-edit pencil + the ⋮ Manage-box sheet, sitting
    # ABOVE a prominent contextual hero (Capture / Open unpacking / the forward
    # lifecycle step) with a quiet "Add manually" link. Per #401 the box is demoted
    # to a slim, softly-shadowed card so the hero — Capture — is the page's focal
    # action, not a feature of a dominant box card (Stitch "Approach 1"). Dimensions
    # and weight live in the Manage sheet; everything secondary lives in
    # Components::Boxes::ManageSheet.
    #
    # Stable id so BoxesController#transition can Turbo-replace the whole region
    # after a lifecycle change — the status chip, the hero action and the sheet's
    # available transitions all shift with status — without reloading the page.
    class HeaderBento < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      ID = "box-header-bento"

      # The prominent, full-width sage hero pill — the page's primary action.
      HERO_CLASS = "w-full inline-flex items-center justify-center gap-3 rounded-full " \
                   "bg-accent-sage px-6 py-5 text-headline-md font-bold text-page " \
                   "transition hover:opacity-90 active:scale-[0.98]"

      def initialize(move:, box:, editable: false)
        @move = move
        @box = box
        @editable = editable
      end

      def view_template
        div(id: ID, class: "flex flex-col gap-6") do
          identity_card
          hero_zone
        end
      end

      private

      # Demoted, softly-shadowed identity card: chips → number → contents subtitle,
      # with the quick-edit pencil + ⋮ Manage sheet in the corner.
      def identity_card
        render Components::Ui::Card.new(padding: "p-5", class: "shadow-soft") do
          div(class: "flex items-start justify-between gap-3") do
            div(class: "flex flex-col gap-2") do
              div(class: "flex flex-wrap gap-2") { chips }
              h2(class: "text-headline-md text-text-warm") { box_title }
              subtitle
            end
            header_actions
          end
        end
      end

      # Quick-edit pencil (editor) + the ⋮ Manage-box sheet (always — it carries the
      # box dimensions and the print actions even for a viewer / archived Move).
      def header_actions
        div(class: "flex shrink-0 items-center gap-1") do
          edit_link if @editable
          render Components::Boxes::ManageSheet.new(
            move: @move, box: @box, editable: @editable, consumed: consumed_transition
          )
        end
      end

      # Contents description as a one-line subtitle; when blank, a quiet
      # "add a description" link to the edit form (where the ✨ AI-suggest lives),
      # for an editable Move only.
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

      # The single contextual primary action for the box's phase, made prominent —
      # with a quiet "Add manually" beneath it (Stitch "Approach 1"). A read-only
      # Move shows the quiet read-only note instead (and, where applicable, the
      # unpacking entry — that surface is open to viewers).
      def hero_zone
        div(class: "flex flex-col items-center gap-2") do
          case hero
          when :unpack then unpack_action
          when :capture then capture_action
          when :transition then forward_transition_action
          end
          add_manually_link if @editable
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
        a(href: move_box_unpacking_path(@move, @box), class: HERO_CLASS) do
          render Components::Icons::Boxes.new(css: "h-6 w-6")
          span { I18n.t("boxes.actions.unpack") }
        end
      end

      def capture_action
        a(href: move_box_capture_path(@move, @box), class: HERO_CLASS) do
          render Components::Icons::Camera.new(css: "h-6 w-6")
          span { I18n.t("boxes.actions.capture") }
        end
      end

      def forward_transition_action
        target = forward_transition
        button_to(
          transition_move_box_path(@move, @box),
          method: :patch, params: { to: target }, form_class: "w-full", class: HERO_CLASS
        ) { span { I18n.t("boxes.actions.#{target}") } }
      end

      # Quiet secondary action under the hero — the "Subtle Add" half of Approach 1.
      def add_manually_link
        a(
          href: new_move_box_item_path(@move, @box),
          class: "text-body-md text-muted transition hover:text-text-warm"
        ) { I18n.t("boxes.actions.add_manually") }
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
