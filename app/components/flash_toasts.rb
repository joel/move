# frozen_string_literal: true

module Components
  class FlashToasts < Components::Base
    include Phlex::Rails::Helpers::Flash

    def view_template
      return unless flash.any?

      div(class: "pointer-events-none fixed right-6 top-20 md:top-6 z-50 " \
                 "flex w-[calc(100vw-3rem)] max-w-sm flex-col gap-3") do
        flash.each do |type, message|
          if type.to_s == "notice"
            render_notice_toast(message)
          else
            render_alert_toast(message)
          end
        end
      end
    end

    private

    def render_notice_toast(message)
      div(
        data: { controller: "toast", toast_timeout_value: "4000" },
        class: "pointer-events-auto flex items-start gap-3 rounded-2xl border border-emerald-300/30 " \
               "bg-[linear-gradient(140deg,rgba(16,185,129,0.12),rgba(15,23,42,0.92))] p-4 text-emerald-100 " \
               "shadow-[0_18px_45px_-30px_rgba(16,185,129,0.6)] transition-all duration-300 ease-out"
      ) do
        div(class: "flex h-9 w-9 items-center justify-center rounded-xl bg-emerald-400/20 text-emerald-200") do
          render Components::Icons::Check.new
        end
        div(class: "min-w-0 flex-1") do
          p(class: "text-sm font-semibold") { "All set" }
          p(class: "mt-1 text-sm text-emerald-100/80") { message }
        end
        render_dismiss_button("emerald")
      end
    end

    def render_alert_toast(message)
      div(
        data: { controller: "toast", toast_timeout_value: "4500" },
        class: "pointer-events-auto flex items-start gap-3 rounded-2xl border border-rose-300/30 " \
               "bg-[linear-gradient(140deg,rgba(244,63,94,0.12),rgba(15,23,42,0.92))] p-4 text-rose-100 " \
               "shadow-[0_18px_45px_-30px_rgba(244,63,94,0.6)] transition-all duration-300 ease-out"
      ) do
        div(class: "flex h-9 w-9 items-center justify-center rounded-xl bg-rose-400/20 text-rose-200") do
          render Components::Icons::Alert.new
        end
        div(class: "min-w-0 flex-1") do
          p(class: "text-sm font-semibold") { "Action needed" }
          p(class: "mt-1 text-sm text-rose-100/80") { message }
        end
        render_dismiss_button("rose")
      end
    end

    def render_dismiss_button(color)
      button(
        type: "button",
        data: { action: "toast#dismiss" },
        class: "flex h-7 w-7 items-center justify-center rounded-full text-#{color}-100/80 " \
               "transition hover:bg-#{color}-200/10 hover:text-#{color}-100",
        aria_label: "Dismiss notification"
      ) do
        render Components::Icons::Close.new(css: "h-3.5 w-3.5")
      end
    end
  end
end
