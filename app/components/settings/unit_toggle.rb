# frozen_string_literal: true

module Components
  module Settings
    # F3 — the measurement-unit toggle (metric / imperial). The selected system is
    # a static pill; the others are button_to PATCHes. Stable id so
    # SettingsController#update_unit_system can Turbo-replace it after a change (the
    # selected pill flips) without reloading the settings page. Viewers / archived
    # Moves see the resolved value read-only.
    class UnitToggle < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      ID = "settings-unit-toggle"

      #: (move: untyped, editable: untyped) -> void
      def initialize(move:, editable:)
        @move = move
        @editable = editable
      end

      #: () -> void
      def view_template
        div(id: ID) do
          if @editable
            div(class: "inline-flex self-start rounded-full border border-card-border bg-card p-1") do
              Move::UNIT_SYSTEMS.each { |system| unit_option(system) }
            end
          else
            span(class: "text-body-md text-text-warm") do
              I18n.t("settings.show.preferences.#{@move.unit_system}")
            end
          end
        end
      end

      private

      #: (untyped system) -> untyped
      def unit_option(system)
        label = I18n.t("settings.show.preferences.#{system}")
        if @move.unit_system == system
          span(class: "#{toggle_pill} bg-surface-container-high text-text-warm", aria_current: "true") { label }
        else
          button_to(
            move_settings_unit_system_path(@move), method: :patch,
                                                   params: { move: { unit_system: system } },
                                                   class: "#{toggle_pill} text-on-surface-variant hover:text-text-warm"
          ) { label }
        end
      end

      #: () -> untyped
      def toggle_pill
        "rounded-full px-6 py-2 text-sm font-semibold transition"
      end
    end
  end
end
