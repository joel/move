# frozen_string_literal: true

module Views
  module Accounts
    class Show < Views::Base
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(user:)
        @user = user
      end

      def view_template
        div(class: "space-y-8") do
          render Components::PageHeader.new(
            section: "Account",
            title: "My account",
            subtitle: "Keep your profile details up to date."
          ) do
            button_to("Sign out", view_context.rodauth.logout_path,
                      method: :post,
                      form: { class: "inline-flex" },
                      class: "ha-button ha-button-secondary")
          end

          render Components::NoticeBanner.new(message: view_context.notice) if view_context.notice.present?

          render Components::AccountDetails.new(user: @user)
          render_security
          render_danger_zone
        end
      end

      private

      # Passwordless passkey (WebAuthn) management: "Add passkey" until the
      # account has one registered, then "Manage passkeys" to review/remove.
      def render_security
        section(class: "space-y-4") do
          h2(class: "ha-overline") { "Security" }
          link_to(
            passkey_path,
            class: "ha-card flex items-center gap-4 p-6 transition " \
                   "hover:bg-[var(--ha-surface-high)]"
          ) do
            span(class: "flex h-10 w-10 flex-shrink-0 items-center justify-center " \
                        "rounded-full bg-[var(--ha-primary-container)]/20 " \
                        "text-[var(--ha-primary)]") do
              render Components::Icons::Key.new(css: "h-5 w-5")
            end
            span(class: "flex-1 font-medium") { passkey_label }
            render Components::Icons::ChevronRight.new(
              css: "h-5 w-5 text-[var(--ha-on-surface-variant)]"
            )
          end
        end
      end

      # Irreversible actions, isolated at the bottom so they're never adjacent to
      # benign controls.
      def render_danger_zone
        section(class: "space-y-4") do
          h2(class: "ha-overline text-[var(--ha-error)]") { "Danger zone" }
          div(class: "ha-card border-[var(--ha-error)]/30 p-6") do
            div(class: "flex flex-wrap items-center justify-between gap-4") do
              div do
                p(class: "font-medium") { "Delete account" }
                p(class: "mt-1 text-sm text-[var(--ha-muted)]") do
                  plain "Permanently remove your account and all of its data."
                end
              end
              # turbo: false — deletion ends in a cross-host redirect to the apex
              # (the current subdomain's tenant may have just been dropped), which
              # Turbo will not follow via fetch; a native submit lets the browser
              # follow the redirect. That also disables data-turbo-confirm, so the
              # confirmation is driven by the `confirm` Stimulus controller.
              button_to("Delete account", view_context.account_path,
                        method: :delete,
                        class: "ha-button ha-button-danger",
                        form: {
                          class: "inline-flex",
                          data: {
                            turbo: false,
                            controller: "confirm",
                            confirm_message_value: "Delete your account permanently?",
                            action: "submit->confirm#confirm"
                          }
                        })
            end
          end
        end
      end

      def passkey_path
        rodauth = view_context.rodauth
        passkey_registered? ? rodauth.webauthn_remove_path : rodauth.webauthn_setup_path
      end

      def passkey_label
        passkey_registered? ? "Manage passkeys" : "Add passkey"
      end

      # rodauth.webauthn_setup? reads the authenticated Rodauth account; guard on
      # logged_in? so the page never raises when current_user is present without a
      # Rodauth session (e.g. request specs that stub current_user).
      def passkey_registered?
        rodauth = view_context.rodauth
        rodauth.logged_in? && rodauth.webauthn_setup?
      end
    end
  end
end
