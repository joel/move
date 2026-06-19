# frozen_string_literal: true

module Components
  module Ui
    # Desktop sidebar (lg+). 280px, blends into the page colour; the active item
    # carries a sage fill. A "New Box" primary action sits at the bottom.
    # Stateless in D0.
    #
    #   render Components::Ui::Sidebar.new(active: :boxes)
    class Sidebar < Components::Base
      def initialize(active: :boxes, destinations: Components::Ui::NavDestinations.default, **attrs)
        @active = active.to_sym
        @destinations = destinations
        @attrs = attrs
      end

      def view_template
        nav(
          class: "hidden lg:flex fixed left-0 top-0 z-40 h-full w-[280px] flex-col " \
                 "gap-stack-gap border-r border-card-border bg-page p-6",
          aria_label: I18n.t("ui.nav.menu"),
          **@attrs
        ) do
          render_brand
          div(class: "flex flex-grow flex-col gap-2") do
            @destinations.each { |dest| item(dest) }
          end
          if Components::Ui::NavDestinations.editor?
            render Components::Ui::Button.new(
              label: I18n.t("ui.buttons.new_box"),
              icon: Components::Icons::Plus,
              href: Components::Ui::NavDestinations::STUB_HREF,
              full_width: true
            )
          end
          render Components::Ui::ThemeToggle.new(
            css: "flex h-10 w-10 items-center justify-center rounded-full " \
                 "text-muted transition hover:bg-card hover:text-text-warm"
          )
        end
      end

      private

      def render_brand
        a(href: moves_path, aria_label: I18n.t("ui.nav.brand_home"),
          class: "mb-8 flex items-center gap-4 rounded-card px-2 py-1 " \
                 "transition hover:bg-card") do
          div(
            class: "flex h-10 w-10 items-center justify-center rounded-full " \
                   "bg-accent-sage text-page text-headline-md font-bold"
          ) { "M" }
          div do
            h1(class: "text-headline-md text-text-warm font-bold") { "Move" }
            p(class: "text-body-md text-muted") { I18n.t("ui.nav.brand_tagline") }
          end
        end
      end

      def item(dest)
        active = dest.key == @active
        a(
          href: dest.href,
          aria_current: (active ? "page" : nil),
          class: [
            "ha-nav-item flex items-center gap-3 rounded-full px-4 py-3",
            (active ? "bg-accent-sage text-page" : "text-muted hover:bg-card hover:text-text-warm")
          ].join(" ")
        ) do
          render dest.icon.new(css: "h-6 w-6")
          span(class: "text-label-caps uppercase") { I18n.t(dest.label_key) }
        end
      end
    end
  end
end
