# frozen_string_literal: true

module Views
  module Agreements
    # The terms-agreement interstitial (#369): the wall every account hits until
    # it accepts the current terms version. Visual language mirrors the adjacent
    # Rodauth auth pages (centered ha-glass card) so the focused, nav-free wall
    # reads as part of the same onboarding family. The only ways forward are
    # "Accept & continue" (POST) or "Sign out".
    class Show < Views::Base
      include Phlex::Rails::Helpers::FormWith

      def view_template
        div(class: "flex min-h-[70vh] items-center justify-center") do
          div(class: "w-full max-w-2xl space-y-8") do
            header_block
            div(class: "ha-glass rounded-[2rem] p-8 shadow-[var(--ha-card-shadow)] space-y-6") do
              terms_block
              accept_form
            end
            sign_out_block
          end
        end
      end

      private

      def header_block
        div(class: "text-center") do
          h1(class: "font-headline text-3xl font-bold tracking-tighter") do
            plain ::Terms::TITLE
          end
          p(class: "mt-2 text-sm text-[var(--ha-on-surface-variant)]") do
            plain "Effective #{::Terms::EFFECTIVE_DATE}. " \
                  "You must accept these terms before you can use the app."
          end
        end
      end

      def terms_block
        p(class: "text-sm text-[var(--ha-on-surface-variant)]") { plain ::Terms::INTRO }

        div(class: "space-y-4") do
          ::Terms::SECTIONS.each do |sec|
            section(class: "space-y-1") do
              h2(class: "text-sm font-semibold text-[var(--ha-on-surface)]") do
                plain sec[:heading]
              end
              p(class: "text-sm text-[var(--ha-on-surface-variant)]") { plain sec[:body] }
            end
          end
        end
      end

      def accept_form
        form_with(
          url: view_context.accept_agreement_path,
          method: :post,
          data: { turbo: false },
          class: "pt-2"
        ) do |form|
          form.submit("Accept & continue", class: "ha-button ha-button-primary w-full")
        end
      end

      def sign_out_block
        p(class: "text-center text-sm text-[var(--ha-on-surface-variant)]") do
          plain "Not ready to accept? "
          a(
            href: view_context.rodauth.logout_path,
            class: "font-medium text-[var(--ha-primary)] underline underline-offset-2"
          ) { "Sign out" }
        end
      end
    end
  end
end
