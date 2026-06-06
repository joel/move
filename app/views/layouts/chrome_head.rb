# frozen_string_literal: true

module Views
  module Layouts
    # Shared <head> + theme-boot for the page layouts (the default TopNav layout
    # and the AppLayout sidebar shell). Keeps asset/theme/meta wiring in one
    # place so the two layouts can't drift.
    module ChromeHead
      include Phlex::Rails::Helpers::CSRFMetaTags
      include Phlex::Rails::Helpers::CSPMetaTag
      include Phlex::Rails::Helpers::StyleSheetLinkTag
      include Phlex::Rails::Helpers::JavaScriptImportmapTags
      include Phlex::Rails::Helpers::ContentFor

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

      def app_name
        Rails.application.config.x.brand_name
      end
    end
  end
end
