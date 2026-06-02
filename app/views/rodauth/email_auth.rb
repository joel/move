# frozen_string_literal: true

module Views
  module Rodauth
    class EmailAuth < Views::Base
      include Phlex::Rails::Helpers::FormWith

      def view_template
        div(class: "space-y-8") do
          div(class: "ha-card p-8") do
            p(class: "ha-overline") do
              plain "Email link"
            end
            h1(class: "mt-2 text-3xl font-semibold tracking-tight sm:text-4xl") do
              plain "Finish signing in"
            end
            p(class: "mt-3 text-sm text-[var(--ha-muted)]") do
              plain "Confirm your sign-in to continue."
            end
          end

          render Components::RodauthFlash.new

          div(class: "ha-card p-6") do
            form_with(
              url: view_context.rodauth.email_auth_path,
              method: :post,
              data: { turbo: false }
            ) do |form|
              raw safe(view_context.rodauth.email_auth_additional_form_tags.to_s)

              form.submit(
                view_context.rodauth.login_button,
                class: "ha-button ha-button-primary w-full"
              )
            end
          end
        end
      end
    end
  end
end
