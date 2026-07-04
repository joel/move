# frozen_string_literal: true

module Views
  module Rodauth
    class CreateAccount < Views::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::ContentTag

      #: () -> void
      def view_template
        div(class: "flex min-h-[70vh] items-center justify-center") do
          div(class: "w-full max-w-md space-y-8") do
            div(class: "text-center") do
              h1(class: "font-headline text-3xl font-bold tracking-tighter") do
                plain "Create account"
              end
              p(class: "mt-2 text-sm text-[var(--ha-on-surface-variant)]") do
                plain "Sign up with your email and we will verify it before you log in."
              end
            end

            render Components::RodauthFlash.new

            div(class: "ha-glass rounded-[2rem] p-8 shadow-[var(--ha-card-shadow)]") do
              form_with(
                url: view_context.rodauth.create_account_path,
                method: :post,
                data: { turbo: false },
                class: "space-y-6"
              ) do |form|
                raw safe(view_context.rodauth.create_account_additional_form_tags.to_s)

                render_login_field(form)
                render_login_confirm_field(form) if view_context.rodauth.require_login_confirmation?

                if view_context.rodauth.create_account_set_password?
                  render_password_field(form)
                  render_password_confirm_field(form) if view_context.rodauth.require_password_confirmation?
                end

                form.submit(
                  view_context.rodauth.create_account_button,
                  class: "ha-button ha-button-primary w-full"
                )
              end
            end
          end
        end
      end

      private

      #: (untyped form) -> untyped
      def render_login_field(form)
        login_error = view_context.rodauth.field_error(view_context.rodauth.login_param)
        aria_attrs = login_error ? { invalid: true, describedby: "login_error_message" } : {}

        div do
          form.label(
            "login",
            view_context.rodauth.login_label,
            class: "text-sm font-medium text-[var(--ha-on-surface-variant)]"
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
              class: "mt-1 block text-xs text-[var(--ha-error)]",
              id: "login_error_message"
            ) { login_error }
          end
        end
      end

      #: (untyped form) -> untyped
      def render_login_confirm_field(form)
        login_confirm_error = view_context.rodauth.field_error(
          view_context.rodauth.login_confirm_param
        )
        aria_attrs = if login_confirm_error
                       { invalid: true, describedby: "login-confirm_error_message" }
                     else
                       {}
                     end

        div do
          form.label(
            "login-confirm",
            view_context.rodauth.login_confirm_label,
            class: "text-sm font-medium text-[var(--ha-on-surface-variant)]"
          )
          form.email_field(
            view_context.rodauth.login_confirm_param,
            value: view_context.params[view_context.rodauth.login_confirm_param],
            id: "login-confirm",
            autocomplete: "email",
            required: true,
            class: "ha-input mt-2",
            aria: aria_attrs
          )
          if login_confirm_error
            span(
              class: "mt-1 block text-xs text-[var(--ha-error)]",
              id: "login-confirm_error_message"
            ) { login_confirm_error }
          end
        end
      end

      #: (untyped form) -> untyped
      def render_password_field(form)
        password_error = view_context.rodauth.field_error(view_context.rodauth.password_param)
        aria_attrs = if password_error
                       { invalid: true, describedby: "password_error_message" }
                     else
                       {}
                     end

        div do
          form.label(
            "password",
            view_context.rodauth.password_label,
            class: "text-sm font-medium text-[var(--ha-on-surface-variant)]"
          )
          form.password_field(
            view_context.rodauth.password_param,
            value: "",
            id: "password",
            autocomplete: view_context.rodauth.password_field_autocomplete_value,
            required: true,
            class: "ha-input mt-2",
            aria: aria_attrs
          )
          if password_error
            span(
              class: "mt-1 block text-xs text-[var(--ha-error)]",
              id: "password_error_message"
            ) { password_error }
          end
        end
      end

      #: (untyped form) -> untyped
      def render_password_confirm_field(form)
        password_confirm_error = view_context.rodauth.field_error(
          view_context.rodauth.password_confirm_param
        )
        aria_attrs = if password_confirm_error
                       { invalid: true, describedby: "password-confirm_error_message" }
                     else
                       {}
                     end

        div do
          form.label(
            "password-confirm",
            view_context.rodauth.password_confirm_label,
            class: "text-sm font-medium text-[var(--ha-on-surface-variant)]"
          )
          form.password_field(
            view_context.rodauth.password_confirm_param,
            value: "",
            id: "password-confirm",
            autocomplete: "new-password",
            required: true,
            class: "ha-input mt-2",
            aria: aria_attrs
          )
          if password_confirm_error
            span(
              class: "mt-1 block text-xs text-[var(--ha-error)]",
              id: "password-confirm_error_message"
            ) { password_confirm_error }
          end
        end
      end
    end
  end
end
