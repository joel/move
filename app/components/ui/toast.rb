# frozen_string_literal: true

module Components
  module Ui
    # Toast notification. Success = sage, error = terracotta/error, info =
    # neutral. Auto-dismisses via the existing `toast` Stimulus controller.
    #
    #   render Components::Ui::Toast.new(variant: :success, message: "Saved")
    class Toast < Components::Base
      VARIANTS = {
        success: {
          icon: Components::Icons::Check,
          # Opaque surface so the message is fully legible; the sage stays as the
          # border + medallion accent (the old /15 fill was unreadable — #162).
          surface: "bg-surface-container-highest border-accent-sage/40 text-text-warm shadow-lg",
          medallion: "bg-accent-sage/20 text-accent-sage",
          title_key: "ui.toast.success_title"
        },
        error: {
          icon: Components::Icons::Alert,
          surface: "bg-surface-container-highest border-secondary/40 text-text-warm shadow-lg",
          medallion: "bg-secondary/20 text-secondary",
          title_key: "ui.toast.error_title"
        },
        info: {
          icon: Components::Icons::Sparkles,
          surface: "bg-surface-container-high border-card-border text-text-warm",
          medallion: "bg-surface-container-highest text-muted",
          title_key: "ui.toast.info_title"
        }
      }.freeze

      def initialize(message:, variant: :info, title: nil, timeout: 4500, **attrs)
        @config = VARIANTS.fetch(variant.to_sym, VARIANTS[:info])
        @message = message
        @title = title || I18n.t(@config[:title_key])
        @timeout = timeout
        @attrs = attrs
      end

      def view_template
        div(
          data: { controller: "toast", toast_timeout_value: @timeout.to_s },
          class: "pointer-events-auto flex items-start gap-3 rounded-card border " \
                 "p-4 transition-all duration-300 ease-out #{@config[:surface]}",
          role: "status",
          **@attrs
        ) do
          div(
            class: "flex h-9 w-9 flex-shrink-0 items-center justify-center " \
                   "rounded-full #{@config[:medallion]}"
          ) do
            render @config[:icon].new(css: "h-5 w-5")
          end
          div(class: "min-w-0 flex-1") do
            p(class: "text-body-md font-bold") { @title }
            p(class: "mt-1 text-body-md text-on-surface-variant") { @message }
          end
          render_dismiss
        end
      end

      private

      def render_dismiss
        button(
          type: "button",
          data: { action: "toast#dismiss" },
          aria_label: I18n.t("ui.buttons.dismiss"),
          class: "flex h-7 w-7 items-center justify-center rounded-full " \
                 "text-muted transition hover:bg-surface-container-highest hover:text-text-warm"
        ) do
          render Components::Icons::Close.new(css: "h-3.5 w-3.5")
        end
      end
    end
  end
end
