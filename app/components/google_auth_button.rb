# frozen_string_literal: true

module Components
  # The "Sign in with Google" affordance. Google registers a single OAuth
  # redirect URI + JS origin (no wildcards), so the flow must run on the apex:
  #
  # - **Apex host:** a real `button_to` POST to the OmniAuth request path. When
  #   the user arrived from a subdomain with `?via=google`, the form auto-submits
  #   on connect so it's effectively one click.
  # - **Org subdomain:** a GET **link** to `https://<apex>/login?via=google` — a
  #   subdomain page can't POST cross-origin to the apex with a valid CSRF token,
  #   so it hands off to the apex, which then auto-starts the flow.
  #
  # Only rendered when both Google credentials are present (gate it with
  # `google_credentials_present?`). One Tap is separate and stays apex-only (it's
  # bound to the page's JS origin and can't be routed).
  class GoogleAuthButton < Components::Base
    include Phlex::Rails::Helpers::ButtonTo
    include Phlex::Rails::Helpers::LinkTo

    BUTTON_CLASS = "ha-button ha-button-secondary w-full " \
                   "flex items-center justify-center gap-3"

    #: (?label: untyped) -> void
    def initialize(label: "Sign in with Google")
      @label = label
    end

    #: () -> void
    def view_template
      return unless view_context.google_credentials_present?

      view_context.on_apex_host? ? apex_button : subdomain_link
    end

    private

    #: () -> untyped
    def apex_button
      button_to(
        view_context.rodauth.omniauth_request_path(:google, **omniauth_forward_params),
        method: :post,
        # data-turbo=false on the FORM: the response is a cross-origin 302 to
        # Google, which Turbo can't follow — force a native submit/redirect.
        form: { data: form_data },
        class: BUTTON_CLASS
      ) { contents }
    end

    # Forward query params that must survive the round-trip to Google and reach
    # the callback via omniauth.params: the originating org (#346) and a Move
    # invitation token (D14 #608 — an invitee who signs in with Google would
    # otherwise drop the token, get a stray personal org, and miss the accept
    # landing). Both are validated server-side before they're honoured, so a
    # stray value is harmless.

    #: () -> untyped
    def omniauth_forward_params
      { org: view_context.params[:org], invite_token: view_context.params[:invite_token] }
        .transform_values { |v| v.to_s.presence }
        .compact
    end

    # When routed here from a subdomain (?via=google), auto-submit on connect.

    #: () -> untyped
    def form_data
      base = { turbo: "false" }
      return base unless auto_start?

      base.merge(controller: "auto-submit", auto_submit_on_connect_value: "true")
    end

    #: () -> untyped
    def auto_start?
      view_context.params[:via].to_s == "google"
    end

    #: () -> untyped
    def subdomain_link
      link_to(apex_google_url, data: { turbo: "false" }, class: BUTTON_CLASS) do
        contents
      end
    end

    # Carry the originating org slug to the apex so the post-auth handoff can
    # target THIS subdomain, not the user's primary org (#346). The apex forwards
    # it through OmniAuth; membership is validated before it's honoured.

    #: () -> untyped
    def apex_google_url
      host = Rails.application.config.action_mailer.default_url_options&.dig(:host)
      url = "https://#{host}/login?via=google"
      slug = view_context.current_tenant
      # Escape defensively even though slugs are format-validated (DNS-label safe).
      url = "#{url}&org=#{CGI.escape(slug)}" if slug.present?
      token = view_context.params[:invite_token].to_s
      token.present? ? "#{url}&invite_token=#{CGI.escape(token)}" : url
    end

    #: () -> untyped
    def contents
      render Components::Icons::Google.new
      span { @label }
    end
  end
end
