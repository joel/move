# frozen_string_literal: true

module Views
  module Invitations
    # The ONE generic failure page for every invitation dead end — unknown,
    # expired, revoked, consumed, or a signed-in account that doesn't match the
    # invited email (Phase D14, #608). Deliberately state-blind so a token
    # holder can't probe which case they hit; the signed-in variant offers a
    # sign-out so the right account can try the link again.
    class Unavailable < Views::Base
      include Phlex::Rails::Helpers::LinkTo
      include Phlex::Rails::Helpers::ButtonTo

      #: (signed_in: untyped) -> void
      def initialize(signed_in:)
        @signed_in = signed_in
      end

      #: () -> void
      def view_template
        div(class: "mx-auto mt-16 max-w-xl rounded-card border border-card-border bg-card p-8") do
          h1(class: "text-headline-lg text-text-warm") { I18n.t("invitations.unavailable.title") }
          p(class: "mt-3 text-body-md text-muted") { I18n.t("invitations.unavailable.body") }
          div(class: "mt-6 flex flex-wrap items-center gap-3") do
            link_to(I18n.t("invitations.unavailable.back_home"), "/",
                    class: "ha-button ha-button-primary")
            sign_out_button if @signed_in
          end
        end
      end

      private

      #: () -> untyped
      def sign_out_button
        button_to(I18n.t("invitations.unavailable.sign_out"), view_context.rodauth.logout_path,
                  method: :post, class: "ha-button")
      end
    end
  end
end
