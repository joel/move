# frozen_string_literal: true

module Components
  # Generic top navigation bar: brand, primary links, a theme toggle and
  # auth-aware actions. Replace or extend this with your app's real nav.
  class TopNav < Components::Base
    include Phlex::Rails::Helpers::LinkTo
    include Phlex::Rails::Helpers::ButtonTo

    def view_template
      header(class: "sticky top-0 z-40 border-b border-[var(--ha-border)]/40 " \
                    "bg-[var(--ha-surface)]/80 backdrop-blur") do
        div(class: "mx-auto flex max-w-5xl items-center justify-between " \
                   "gap-4 px-6 py-3 sm:px-10") do
          render_brand
          nav(class: "flex items-center gap-2 sm:gap-3") do
            render_primary_links
            render_theme_toggle
            render_auth_actions
          end
        end
      end
    end

    private

    def render_brand
      link_to(view_context.root_path, class: "flex items-center gap-2") do
        span(class: "flex h-8 w-8 items-center justify-center rounded-xl " \
                    "ha-gradient-aura text-sm font-bold text-white") do
          plain app_name.first.upcase
        end
        span(class: "font-headline text-lg font-bold tracking-tight") do
          plain app_name
        end
      end
    end

    def render_primary_links
      link_to("Posts", view_context.posts_path, class: nav_link_class)
      return unless current_user && view_context.allowed_to?(:index?, User)

      link_to("Users", view_context.users_path, class: nav_link_class)
    end

    def render_theme_toggle
      button(
        type: "button",
        data: { action: "theme#toggle" },
        aria_label: "Toggle theme",
        class: "flex h-9 w-9 items-center justify-center rounded-full " \
               "text-[var(--ha-muted)] transition hover:bg-[var(--ha-surface-high)] " \
               "hover:text-[var(--ha-text)]"
      ) do
        span(data: { theme_target: "iconLight" }) do
          render Components::Icons::Sun.new(css: "h-5 w-5")
        end
        span(data: { theme_target: "iconDark" }, class: "hidden") do
          render Components::Icons::Moon.new(css: "h-5 w-5")
        end
      end
    end

    def render_auth_actions
      if current_user
        link_to("Account", view_context.account_path, class: nav_link_class)
        button_to("Sign out", view_context.rodauth.logout_path,
                  method: :post,
                  form: { class: "inline-flex" },
                  class: "ha-button ha-button-secondary !px-4 !py-2 text-sm")
      else
        link_to("Sign in", view_context.rodauth.login_path,
                class: "ha-button ha-button-primary !px-4 !py-2 text-sm")
      end
    end

    def nav_link_class
      "rounded-full px-3 py-2 text-sm font-medium text-[var(--ha-muted)] " \
        "transition hover:bg-[var(--ha-surface-high)] hover:text-[var(--ha-text)]"
    end

    def current_user
      view_context.current_user
    end

    def app_name
      Rails.application.class.module_parent_name
    end
  end
end
