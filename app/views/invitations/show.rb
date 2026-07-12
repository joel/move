# frozen_string_literal: true

module Views
  module Invitations
    # Apex landing for a Move invitation (Phase D14, #608): names the inviter,
    # Move, Organization, and role, then routes by auth state — an Accept button
    # for the signed-in invited email, otherwise sign-in / create-account links
    # that carry the invite token (Rodauth POSTs drop query params, so the auth
    # side re-carries it via hidden fields — see rodauth_main).
    class Show < Views::Base
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::Routes

      #: (invitation: untyped, raw_token: untyped, move_name: untyped, state: untyped) -> void
      def initialize(invitation:, raw_token:, move_name:, state:)
        @invitation = invitation
        @raw_token = raw_token
        @move_name = move_name
        @state = state
      end

      #: () -> void
      def view_template
        div(class: "mx-auto mt-16 max-w-xl rounded-card border border-card-border bg-card p-8") do
          h1(class: "text-headline-lg text-text-warm") { I18n.t("invitations.show.title") }
          p(class: "mt-3 text-body-md text-muted") { intro_copy }
          p(class: "mt-1 text-body-md text-muted") do
            I18n.t("invitations.show.role_intro",
                   role: I18n.t("members.roles.#{@invitation.role}"))
          end
          div(class: "mt-6 flex flex-wrap items-center gap-3") { cta }
        end
      end

      private

      #: () -> String
      def intro_copy
        move = @move_name || @invitation.organization.name
        if (inviter = @invitation.invited_by&.name.presence)
          I18n.t("invitations.show.invited_by",
                 inviter: inviter, move: move, organization: @invitation.organization.name)
        else
          I18n.t("invitations.show.invited_anonymous",
                 move: move, organization: @invitation.organization.name)
        end
      end

      #: () -> untyped
      def cta
        case @state
        when :acceptable then accept_button
        when :sign_in
          auth_link(I18n.t("invitations.show.sign_in"), view_context.rodauth.login_path)
        else
          auth_link(I18n.t("invitations.show.create_account"),
                    view_context.rodauth.create_account_path)
        end
      end

      # turbo: false — a successful accept ends in a cross-host redirect to the
      # org subdomain's session handoff, which Turbo's form submission can't
      # follow (it can't read a cross-origin 302), so the button would appear to
      # do nothing. A full-page POST follows the redirect. Same rule as the
      # account-deletion button (app/views/accounts/show.rb).

      #: () -> untyped
      def accept_button
        button_to(
          I18n.t("invitations.show.accept"),
          invitation_acceptance_path,
          method: :post, class: "ha-button ha-button-primary",
          params: { token: @raw_token }, form: { data: { turbo: false } }
        )
      end

      # The token and the invited email ride the query string so the auth forms
      # can prefill the login and re-carry the token through hidden fields. The
      # prefill key is Rodauth's login_param ("email" in this app, not the gem
      # default "login") — the form components read params[login_param].

      #: (untyped label, untyped path) -> untyped
      def auth_link(label, path)
        query = { view_context.rodauth.login_param => @invitation.email,
                  invite_token: @raw_token }.to_query
        link_to(label, "#{path}?#{query}", class: "ha-button ha-button-primary")
      end
    end
  end
end
