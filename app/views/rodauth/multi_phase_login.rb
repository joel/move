# frozen_string_literal: true

module Views
  module Rodauth
    class MultiPhaseLogin < Views::Base
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::ButtonTo

      def view_template
        login_value = view_context.params[
          view_context.rodauth.login_param
        ]

        div(class: "space-y-8") do
          render_header(login_value)
          render Components::RodauthFlash.new
          render_auth_methods
          render_google_option if google_configured?
          render_footer
        end
      end

      private

      def render_header(login_value)
        div(class: "ha-card p-8") do
          p(class: "ha-overline") { "Access" }
          h1(class: "mt-2 text-3xl font-semibold " \
                    "tracking-tight sm:text-4xl") do
            plain "Choose a sign-in method"
          end
          p(class: "mt-3 text-sm text-[var(--ha-muted)]") do
            plain "Continue for "
            span(class: "font-semibold text-[var(--ha-text)]") do
              plain login_value
            end
            plain "."
          end
        end
      end

      def render_auth_methods
        div(class: "grid gap-4 md:grid-cols-2") do
          raw safe(
            view_context.rodauth
                        .render_multi_phase_login_forms.to_s
          )
        end
      end

      def render_google_option
        div(class: "ha-card p-6") do
          button_to(
            view_context.rodauth.omniauth_request_path(:google),
            method: :post,
            data: { turbo: false },
            class: "ha-button ha-button-secondary w-full " \
                   "flex items-center justify-center gap-3"
          ) do
            render Components::Icons::Google.new
            span { "Sign in with Google" }
          end
        end
      end

      def render_footer
        div(
          class: "ha-card p-6 flex flex-col gap-3 sm:flex-row " \
                 "sm:items-center sm:justify-between"
        ) do
          p(class: "text-sm text-[var(--ha-muted)]") do
            plain "Need to use a different email?"
          end
          link_to(
            "Start over",
            view_context.rodauth.login_path,
            class: "ha-button ha-button-secondary"
          )
        end
      end

      def google_configured?
        ENV["GOOGLE_CLIENT_ID"].present?
      end
    end
  end
end
