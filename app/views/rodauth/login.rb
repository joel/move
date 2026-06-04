# frozen_string_literal: true

module Views
  module Rodauth
    class Login < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      def view_template
        div(class: "flex min-h-[70vh] items-center justify-center") do
          div(class: "w-full max-w-md space-y-8") do
            render_brand_header
            render Components::RodauthFlash.new
            render_login_panel
          end
        end
      end

      private

      def render_brand_header
        div(class: "text-center") do
          div(class: "mx-auto flex h-16 w-16 items-center " \
                     "justify-center rounded-2xl " \
                     "ha-gradient-aura shadow-lg") do
            span(class: "text-2xl font-bold text-page") { app_name.first.upcase }
          end
          h1(class: "mt-4 font-headline text-3xl font-bold " \
                    "tracking-tighter") do
            plain app_name
          end
          p(class: "mt-2 text-sm " \
                   "text-[var(--ha-on-surface-variant)]") do
            plain "Sign in to your account"
          end
        end
      end

      def render_login_panel
        div(class: "ha-glass rounded-[2rem] p-8 " \
                   "shadow-[var(--ha-card-shadow)]") do
          h2(class: "font-headline text-xl font-bold") do
            plain "Sign in"
          end
          p(class: "mt-1 text-sm " \
                   "text-[var(--ha-on-surface-variant)]") do
            plain "Enter your email to choose a passkey or " \
                  "request a sign-in link."
          end

          div(class: "mt-6") do
            render Components::RodauthLoginForm.new
          end

          render Components::WebauthnAutofill.new

          render_google_section if google_configured?

          render Components::RodauthLoginFormFooter.new
        end
      end

      def render_google_section
        render_social_divider
        render_google_button("Sign in with Google")
      end

      def render_social_divider
        div(class: "relative my-6") do
          div(class: "absolute inset-0 flex items-center") do
            div(class: "w-full border-t " \
                       "border-[var(--ha-border)]/30")
          end
          div(class: "relative flex justify-center text-xs") do
            span(
              class: "bg-white dark:bg-[var(--ha-surface)] " \
                     "px-4 text-[var(--ha-muted)]"
            ) { "or continue with" }
          end
        end
      end

      def render_google_button(label)
        button_to(
          view_context.rodauth.omniauth_request_path(:google),
          method: :post,
          data: { turbo: false },
          class: "ha-button ha-button-secondary w-full " \
                 "flex items-center justify-center gap-3"
        ) do
          render Components::Icons::Google.new
          span { label }
        end
      end

      def google_configured?
        ENV["GOOGLE_CLIENT_ID"].present?
      end

      def app_name
        Rails.application.class.module_parent_name
      end
    end
  end
end
