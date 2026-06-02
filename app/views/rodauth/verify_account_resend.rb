# frozen_string_literal: true

module Views
  module Rodauth
    class VerifyAccountResend < Views::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::ContentTag

      def view_template
        div(class: "space-y-8") do
          div(class: "ha-card p-8") do
            p(class: "ha-overline") do
              plain "Verify"
            end
            h1(class: "mt-2 text-3xl font-semibold tracking-tight sm:text-4xl") do
              plain "Resend verification"
            end
            p(class: "mt-3 text-sm text-[var(--ha-muted)]") do
              plain "Need a fresh verification email? We'll send another link."
            end
          end

          render Components::RodauthFlash.new

          div(class: "ha-card p-6") do
            form_with(
              url: view_context.rodauth.verify_account_resend_path,
              method: :post,
              data: { turbo: false },
              class: "space-y-6"
            ) do |form|
              raw safe(view_context.rodauth.verify_account_resend_additional_form_tags.to_s)

              div(class: "text-sm text-[var(--ha-muted)]") do
                raw safe(view_context.rodauth.verify_account_resend_explanatory_text.to_s)
              end

              if view_context.params[view_context.rodauth.login_param]
                form.hidden_field(
                  view_context.rodauth.login_param,
                  value: view_context.params[view_context.rodauth.login_param]
                )
              else
                render_login_field(form)
              end

              form.submit(
                view_context.rodauth.verify_account_resend_button,
                class: "ha-button ha-button-primary w-full"
              )
            end
          end
        end
      end

      private

      def render_login_field(form)
        login_error = view_context.rodauth.field_error(view_context.rodauth.login_param)
        aria_attrs = login_error ? { invalid: true, describedby: "login_error_message" } : {}

        div do
          form.label(
            "login",
            view_context.rodauth.login_label,
            class: "text-sm font-semibold text-[var(--ha-muted)]"
          )
          form.email_field(
            view_context.rodauth.login_param,
            value: view_context.params[view_context.rodauth.login_param],
            id: "login",
            autocomplete: "email",
            required: true,
            class: "ha-input mt-2",
            aria: aria_attrs
          )
          if login_error
            span(
              class: "mt-1 block text-xs text-red-500",
              id: "login_error_message"
            ) { login_error }
          end
        end
      end
    end
  end
end
