# frozen_string_literal: true

module Views
  module Shared
    class Unauthorized < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def view_template
        div(
          class: "mx-auto max-w-xl rounded-3xl border border-white/10 " \
                 "bg-[linear-gradient(140deg,var(--ha-panel),var(--ha-panel-strong))] p-8 " \
                 "text-[var(--ha-text)] shadow-[0_20px_60px_-45px_rgba(15,23,42,0.6)]"
        ) do
          h1(class: "text-lg font-semibold tracking-tight") { "Sign in required" }
          p(class: "mt-2 text-sm text-[var(--ha-muted)]") do
            plain "You need an account to perform that action."
          end
          div(class: "mt-5 flex flex-wrap gap-3") do
            link_to("Sign in", view_context.rodauth.login_path, class: "ha-button ha-button-primary")
          end
        end
      end
    end
  end
end
