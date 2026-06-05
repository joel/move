# frozen_string_literal: true

module Views
  module Layouts
    class ApplicationLayout < Components::Base
      include Phlex::Rails::Layout
      include Phlex::Rails::Helpers::CSRFMetaTags
      include Phlex::Rails::Helpers::CSPMetaTag
      include Phlex::Rails::Helpers::StyleSheetLinkTag
      include Phlex::Rails::Helpers::JavaScriptImportmapTags
      include Phlex::Rails::Helpers::ContentFor

      def view_template(&)
        doctype
        html(class: "dark") do
          render_head
          body(
            class: "min-h-screen bg-page text-text-warm antialiased",
            data: { controller: "theme" }
          ) do
            render Components::FlashToasts.new
            render Components::GoogleOneTap.new
            render Components::TopNav.new
            render_main(&)
          end
        end
      end

      private

      def render_head
        head do
          render_theme_boot_script
          title { content_for(:title) || app_name }
          meta(name: "viewport", content: "width=device-width,initial-scale=1")
          meta(name: "theme-color", content: "#2a2822")
          csrf_meta_tags
          csp_meta_tag
          yield(:head) if content_for?(:head)
          link(rel: "icon", href: "/icon.png", type: "image/png")
          link(rel: "icon", href: "/icon.svg", type: "image/svg+xml")
          stylesheet_link_tag(:app, data: { turbo_track: "reload" })
          javascript_importmap_tags
        end
      end

      # Apply the persisted theme before first paint (no flash of light). Dark is
      # the default; an explicit "light" choice or "system" preference is honoured.
      def render_theme_boot_script
        script do
          # Static, developer-authored boot script with no user input — safe.
          raw(safe( # rubocop:disable Rails/OutputSafety
                '(function(){try{var t=localStorage.getItem("theme");' \
                'var d=t?t==="dark":true;' \
                'if(t==="system"){d=window.matchMedia("(prefers-color-scheme: dark)").matches;}' \
                'document.documentElement.classList.toggle("dark",d);}' \
                'catch(e){document.documentElement.classList.add("dark");}})();'
              ))
        end
      end

      def render_main(&)
        main(class: "relative") do
          render_background_decorations
          div(class: "relative px-6 py-8 sm:px-10") do
            div(class: "mx-auto max-w-5xl ha-fade-in", &)
          end
        end
      end

      def render_background_decorations
        div(class: "pointer-events-none fixed inset-0 -z-10") do
          div(class: "absolute -right-48 -top-48 h-[500px] w-[500px] " \
                     "rounded-full bg-[var(--ha-primary-container)] " \
                     "opacity-[0.12] blur-[120px]")
          div(class: "absolute -bottom-24 -left-24 h-[400px] w-[400px] " \
                     "rounded-full bg-[var(--ha-surface-high)] " \
                     "opacity-[0.25] blur-[100px]")
        end
      end

      def app_name
        Rails.application.config.x.brand_name
      end
    end
  end
end
