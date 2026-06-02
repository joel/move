# frozen_string_literal: true

module Components
  class RodauthLoginForm < Components::Base
    include Phlex::Rails::Helpers::FormWith
    include Phlex::Rails::Helpers::ContentTag

    def view_template
      form_with(
        url: view_context.rodauth.login_path,
        method: :post,
        data: { turbo: false },
        class: "space-y-6"
      ) do |form|
        raw safe(view_context.rodauth.login_additional_form_tags.to_s)

        if view_context.rodauth.skip_login_field_on_login?
          render_readonly_login_field(form)
        else
          render_login_field(form)
        end

        render_password_field(form) unless view_context.rodauth.skip_password_field_on_login?

        form.submit(
          view_context.rodauth.login_button,
          class: "ha-button ha-button-primary w-full"
        )
      end
    end

    private

    def render_readonly_login_field(form)
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
          readonly: true,
          class: "ha-input mt-2 opacity-80"
        )
      end
    end

    def render_login_field(form)
      login_error = view_context.rodauth.field_error(view_context.rodauth.login_param)

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
          autocomplete: view_context.rodauth.login_field_autocomplete_value,
          required: true,
          class: "ha-input mt-2",
          aria: (
            { invalid: true, describedby: "login_error_message" } if login_error
          )
        )
        if login_error
          content_tag(
            :span,
            login_error,
            class: "mt-1 block text-xs text-[var(--ha-error)]",
            id: "login_error_message"
          )
        end
      end
    end

    def render_password_field(form)
      password_error = view_context.rodauth.field_error(view_context.rodauth.password_param)

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
          aria: (
            { invalid: true, describedby: "password_error_message" } if password_error
          )
        )
        if password_error
          content_tag(
            :span,
            password_error,
            class: "mt-1 block text-xs text-[var(--ha-error)]",
            id: "password_error_message"
          )
        end
      end
    end
  end
end
