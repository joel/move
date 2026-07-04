# frozen_string_literal: true

module Components
  module Ui
    # Inline auto-save indicator for C3. The element always carries the stable
    # `item-save-status` id so the items#update Turbo Stream can replace it after
    # each save. Idle = an empty placeholder; :saved = a sage "Saved ✓" that fades
    # (save_status controller); :error = a persistent error message.
    #
    #   render Components::Ui::SaveStatus.new(state: :saved)
    class SaveStatus < Components::Base
      ID = "item-save-status"

      #: (?state: untyped, ?message: untyped) -> void
      def initialize(state: :idle, message: nil)
        @state = state
        @message = message
      end

      #: () -> void
      def view_template
        case @state
        when :saved then badge(saved: true)
        when :error then badge(saved: false)
        else span(id: ID, class: "hidden")
        end
      end

      private

      #: (saved: bool) -> untyped
      def badge(saved:)
        span(
          id: ID,
          # Only the success badge auto-fades; an error stays put until the next save.
          data: (saved ? { controller: "save-status" } : {}),
          class: "inline-flex items-center gap-1.5 text-label-caps uppercase " \
                 "transition-opacity duration-500 #{saved ? "text-accent-sage" : "text-error"}"
        ) do
          render(saved ? Components::Icons::Check.new(css: "h-4 w-4") : Components::Icons::Alert.new(css: "h-4 w-4"))
          plain(saved ? I18n.t("items.show.saved") : (@message || I18n.t("items.show.save_failed")))
        end
      end
    end
  end
end
