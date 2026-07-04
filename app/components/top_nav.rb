# frozen_string_literal: true

module Components
  # Generic top navigation bar: brand, primary links, a theme toggle and
  # auth-aware actions. Replace or extend this with your app's real nav.
  class TopNav < Components::Base
    include Phlex::Rails::Helpers::LinkTo

    #: () -> void
    def view_template
      header(class: "sticky top-0 z-40 border-b border-[var(--ha-border)]/40 " \
                    "bg-[var(--ha-surface)]/80 backdrop-blur") do
        div(class: "mx-auto flex max-w-5xl items-center justify-between " \
                   "gap-4 px-6 py-3 sm:px-10") do
          render_brand
          nav(class: "flex items-center gap-2 sm:gap-3") do
            render_theme_toggle
            render_auth_actions
          end
        end
      end
    end

    private

    #: () -> untyped
    def render_brand
      link_to(view_context.root_path, class: "flex items-center gap-2") do
        span(class: "flex h-8 w-8 items-center justify-center rounded-xl " \
                    "ha-gradient-aura text-sm font-bold text-page") do
          plain app_name.first.upcase
        end
        span(class: "font-headline text-lg font-bold tracking-tight") do
          plain app_name
        end
      end
    end

    #: () -> untyped
    def render_theme_toggle
      render Components::Ui::ThemeToggle.new
    end

    #: () -> untyped
    def render_auth_actions
      if current_user
        link_to(view_context.account_path,
                aria: { label: "Account" },
                class: "flex h-9 w-9 items-center justify-center rounded-full " \
                       "text-accent-sage transition hover:bg-[var(--ha-surface-high)] " \
                       "hover:opacity-80") do
          render Components::Icons::UserCircle.new(css: "h-7 w-7")
        end
      else
        link_to("Sign in", view_context.rodauth.login_path,
                class: "ha-button ha-button-primary !px-4 !py-2 text-sm")
      end
    end

    #: () -> untyped
    def current_user
      view_context.current_user
    end

    #: () -> untyped
    def app_name
      Rails.application.config.x.brand_name
    end
  end
end
