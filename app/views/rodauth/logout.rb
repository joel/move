# frozen_string_literal: true

module Views
  module Rodauth
    class Logout < Views::Base
      include Phlex::Rails::Helpers::FormWith

      def view_template
        div(class: "space-y-8") do
          div(class: "ha-card p-8") do
            p(class: "ha-overline") do
              plain "Account"
            end
            h1(class: "mt-2 text-3xl font-semibold tracking-tight sm:text-4xl") do
              plain "Sign out"
            end
            p(class: "mt-3 text-sm text-[var(--ha-muted)]") do
              plain "Confirm to end this session."
            end
          end

          render Components::RodauthFlash.new

          div(class: "ha-card p-6") do
            form_with(
              url: view_context.rodauth.logout_path,
              method: :post,
              data: { turbo: false },
              class: "space-y-6"
            ) do |form|
              raw safe(view_context.rodauth.logout_additional_form_tags.to_s)

              if view_context.rodauth.features.include?(:active_sessions)
                label(
                  for: "global-logout",
                  class: "flex items-center gap-3 text-sm text-[var(--ha-muted)]"
                ) do
                  form.check_box(
                    view_context.rodauth.global_logout_param,
                    id: "global-logout",
                    class: "h-4 w-4",
                    include_hidden: false
                  )
                  span { plain view_context.rodauth.global_logout_label }
                end
              end

              form.submit(
                view_context.rodauth.logout_button,
                class: "ha-button ha-button-danger w-full"
              )
            end
          end
        end
      end
    end
  end
end
