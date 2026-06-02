# frozen_string_literal: true

module Components
  class RodauthEmailAuthRequestForm < Components::Base
    include Phlex::Rails::Helpers::FormWith

    def view_template
      div(class: "ha-card p-6 space-y-6") do
        div do
          p(class: "ha-overline") do
            plain "Email link"
          end
          h2(class: "mt-2 text-lg font-semibold") { "Send a sign-in link" }
          p(class: "mt-2 text-sm text-[var(--ha-muted)]") do
            plain "Receive a one-time link to finish signing in."
          end
        end

        form_with(
          url: view_context.rodauth.email_auth_request_path,
          method: :post,
          data: { turbo: false },
          class: "space-y-6"
        ) do |form|
          raw safe(view_context.rodauth.email_auth_request_additional_form_tags.to_s)
          form.hidden_field(
            view_context.rodauth.login_param,
            value: view_context.params[view_context.rodauth.login_param]
          )
          form.submit(
            view_context.rodauth.email_auth_request_button,
            class: "ha-button ha-button-primary w-full"
          )
        end
      end
    end
  end
end
