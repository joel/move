# frozen_string_literal: true

module Views
  module Rodauth
    class WebauthnAuth < Views::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::JavaScriptIncludeTag

      def view_template
        cred = view_context.rodauth.webauthn_credential_options_for_get

        div(class: "ha-card p-6 space-y-6") do
          div do
            p(class: "ha-overline") do
              plain "Passkey"
            end
            h2(class: "mt-2 text-lg font-semibold") { plain "Use a passkey" }
            p(class: "mt-2 text-sm text-[var(--ha-muted)]") do
              plain "Authenticate with your device for a passwordless sign-in."
            end
          end

          form_with(
            url: view_context.rodauth.webauthn_auth_form_path,
            method: :post,
            id: "webauthn-auth-form",
            data: { credential_options: cred.as_json.to_json, turbo: false },
            class: "space-y-6"
          ) do |form|
            raw safe(view_context.rodauth.webauthn_auth_additional_form_tags.to_s)

            form.hidden_field(
              view_context.rodauth.webauthn_auth_challenge_param,
              value: cred.challenge
            )
            form.hidden_field(
              view_context.rodauth.webauthn_auth_challenge_hmac_param,
              value: view_context.rodauth.compute_hmac(cred.challenge)
            )
            form.text_field(
              view_context.rodauth.webauthn_auth_param,
              value: "",
              id: "webauthn-auth",
              class: "hidden",
              aria: { hidden: "true" }
            )

            div(id: "webauthn-auth-button") do
              form.submit(
                view_context.rodauth.webauthn_auth_button,
                class: "ha-button ha-button-primary w-full"
              )
            end
          end
        end

        javascript_include_tag(
          view_context.rodauth.webauthn_auth_js_path,
          extname: false
        )
      end
    end
  end
end
