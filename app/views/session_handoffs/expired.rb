# frozen_string_literal: true

module Views
  module SessionHandoffs
    # Shown on the org subdomain when a handoff token is missing, expired, already
    # used, or minted for another tenant (#280). Because cookies are host-only, a
    # failed handoff has no subdomain session to carry a flash back to the apex, so
    # we render in place and link to the apex login (where every auth flow starts).
    class Expired < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      #: (login_url: untyped) -> void
      def initialize(login_url:)
        @login_url = login_url
      end

      #: () -> void
      def view_template
        div(
          class: "mx-auto max-w-xl rounded-3xl border border-white/10 " \
                 "bg-[linear-gradient(140deg,var(--ha-panel),var(--ha-panel-strong))] p-8 " \
                 "text-[var(--ha-text)] shadow-[0_20px_60px_-45px_rgba(15,23,42,0.6)]"
        ) do
          h1(class: "text-lg font-semibold tracking-tight") { "Sign-in link expired" }
          p(class: "mt-2 text-sm text-[var(--ha-muted)]") do
            plain "This sign-in link has expired or was already used. " \
                  "Please sign in again to continue."
          end
          div(class: "mt-5 flex flex-wrap gap-3") do
            link_to("Sign in", @login_url, class: "ha-button ha-button-primary")
          end
        end
      end
    end
  end
end
