# frozen_string_literal: true

module Components
  class WebauthnAutofill < Components::Base
    include Phlex::Rails::Helpers::JavaScriptIncludeTag

    def view_template
      return unless show?

      cred = view_context.rodauth.webauthn_credential_options_for_get

      form(
        method: "post",
        action: view_context.rodauth.webauthn_login_path,
        id: "webauthn-login-form",
        data: {
          credential_options: cred.as_json.to_json,
          turbo: "false"
        },
        style: "display:none"
      ) do
        raw safe(
          view_context.rodauth
                      .webauthn_auth_additional_form_tags.to_s
        )
        raw safe(
          view_context.rodauth.csrf_tag(
            view_context.rodauth.webauthn_login_path
          )
        )

        input(
          type: "hidden",
          name: view_context.rodauth.webauthn_auth_challenge_param,
          value: cred.challenge
        )
        input(
          type: "hidden",
          name: view_context.rodauth
                            .webauthn_auth_challenge_hmac_param,
          value: view_context.rodauth.compute_hmac(cred.challenge)
        )
        input(
          type: "text",
          name: view_context.rodauth.webauthn_auth_param,
          id: "webauthn-auth",
          value: "",
          class: "hidden",
          aria: { hidden: "true" }
        )
      end

      javascript_include_tag(
        view_context.rodauth.webauthn_autofill_js_path,
        extname: false
      )
    end

    private

    def show?
      view_context.rodauth.respond_to?(:webauthn_autofill?) &&
        view_context.rodauth.webauthn_autofill? &&
        !view_context.rodauth.logged_in?
    end
  end
end
