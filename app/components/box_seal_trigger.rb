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

    # `trigger_class` / `trigger_icon` let a caller (the Manage-box sheet) render
    # the seal trigger as a left-aligned sheet row instead of the default sage
    # pill; the lazy describe-before-sealing dialog is identical either way.
    def initialize(move:, box:, trigger_class: nil, trigger_icon: nil)
      @move = move
      @box = box
      @trigger_class = trigger_class || default_trigger_class
      @trigger_icon = trigger_icon
    end

    def view_template
      div(data: { controller: "modal" }) do
        button(type: "button", data: { action: "modal#open" }, class: @trigger_class) do
          render @trigger_icon.new(css: "h-5 w-5") if @trigger_icon
          span { I18n.t("boxes.actions.seal") }
        end

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

    private

    def default_trigger_class
      "inline-flex w-full items-center justify-center rounded-full bg-accent-sage " \
        "px-6 py-3 text-sm font-bold text-page transition hover:opacity-90 active:scale-[0.98]"
    end
  end
end
