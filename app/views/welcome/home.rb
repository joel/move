# frozen_string_literal: true

module Views
  module Welcome
    class Home < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def view_template
        if view_context.current_user
          render_logged_in
        else
          render_logged_out
        end
      end

      private

      def render_logged_in
        div(class: "mx-auto w-full max-w-md space-y-8 text-center") do
          section do
            h1(class: "font-headline text-4xl font-bold tracking-tighter md:text-5xl") do
              plain "Welcome, #{user_first_name}"
            end
            p(class: "mt-4 text-lg text-[var(--ha-on-surface-variant)]") do
              plain "You're signed in. This is your starting point — build from here."
            end
          end
          div(class: "flex flex-wrap justify-center gap-3") do
            link_to("Browse posts", view_context.posts_path,
                    class: "ha-button ha-button-primary")
            link_to("My account", view_context.account_path,
                    class: "ha-button ha-button-secondary")
          end
        end
      end

      def render_logged_out
        div(class: "mx-auto w-full max-w-md space-y-8") do
          section do
            h1(class: "font-headline text-4xl font-bold tracking-tighter md:text-5xl") do
              plain "Welcome to #{app_name}"
            end
            p(class: "mt-2 text-lg text-[var(--ha-on-surface-variant)]") do
              plain "Passwordless authentication with passkeys, email links and Google."
            end
          end
          render_access_card
        end
      end

      def render_access_card
        div(class: "ha-card p-6 ha-rise") do
          p(class: "ha-overline") { "Get started" }
          h2(class: "mt-2 font-headline text-2xl font-bold") do
            plain "Sign in or create an account"
          end
          p(class: "mt-3 text-sm text-[var(--ha-on-surface-variant)]") do
            plain "Create an account in seconds — no password required."
          end
          div(class: "mt-6 flex flex-wrap gap-3") do
            link_to("Sign in", view_context.rodauth.login_path,
                    class: "ha-button ha-button-primary")
            link_to("Create account", view_context.rodauth.create_account_path,
                    class: "ha-button ha-button-secondary")
          end
        end
      end

      def user_first_name
        user = view_context.current_user
        return "there" unless user

        name = user.name.presence
        name ? name.split.first : user.email.split("@").first
      end

      def app_name
        Rails.application.config.x.brand_name
      end
    end
  end
end
