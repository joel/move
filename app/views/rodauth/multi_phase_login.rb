# frozen_string_literal: true

module Views
  module Rodauth
    class MultiPhaseLogin < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      #: () -> void
      def view_template
        login_value = view_context.params[
          view_context.rodauth.login_param
        ]

        div(class: "space-y-8") do
          render_header(login_value)
          render Components::RodauthFlash.new
          render_auth_methods
          render_google_option if view_context.google_credentials_present?
          render_footer
        end
      end

      private

      #: (untyped login_value) -> untyped
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

      #: () -> untyped
      def render_auth_methods
        div(class: "grid gap-4 md:grid-cols-2") do
          raw safe(
            view_context.rodauth
                        .render_multi_phase_login_forms.to_s
          )
        end
      end

      #: () -> untyped
      def render_google_option
        div(class: "ha-card p-6") do
          render Components::GoogleAuthButton.new
        end
      end

      #: () -> untyped
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
    end
  end
end
