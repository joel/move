# frozen_string_literal: true

module Components
  # B1 — the "Seal" action when a box has items but no description yet: a trigger
  # button plus a native-<dialog> modal that lazy-loads the "describe before
  # sealing" frame (so the AI suggestion only runs when the modal opens). Both the
  # trigger and the dialog sit inside one modal Stimulus controller. When the
  # description is already set (or the box is empty), the detail view keeps the
  # plain one-click button_to instead of rendering this.
  class BoxSealTrigger < Components::Base
    register_element :turbo_frame

    def initialize(move:, box:)
      @move = move
      @box = box
    end

    def view_template
      div(data: { controller: "modal" }) do
        button(
          type: "button", data: { action: "modal#open" },
          class: "inline-flex w-full items-center justify-center rounded-full bg-accent-sage " \
                 "px-6 py-3 text-sm font-bold text-page transition hover:opacity-90 active:scale-[0.98]"
        ) { I18n.t("boxes.actions.seal") }

        dialog(
          class: "ha-modal", data: { modal_target: "dialog", action: "click->modal#backdropClose" }
        ) do
          turbo_frame(id: "seal_box", src: seal_move_box_path(@move, @box), loading: "lazy") do
            div(class: "flex items-center justify-center py-10") do
              render Components::Icons::Sparkles.new(css: "h-6 w-6 animate-pulse text-accent-sage")
            end
          end
        end
      end
    end
  end
end
