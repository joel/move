# frozen_string_literal: true

module Components
  module Ui
    # Mobile bottom navigation (hidden on lg+). Active tab is a sage pill; the
    # Scan destination is an elevated centre button. Stateless in D0.
    #
    #   render Components::Ui::BottomTabBar.new(active: :boxes)
    class BottomTabBar < Components::Base
      def initialize(active: :boxes, destinations: Components::Ui::NavDestinations.default, **attrs)
        @active = active.to_sym
        @destinations = destinations
        @attrs = attrs
      end

      def view_template
        nav(
          class: "lg:hidden fixed bottom-0 left-0 z-50 flex w-full items-center " \
                 "justify-around rounded-t-card border-t border-card-border " \
                 "bg-card px-4 pb-6 pt-3",
          aria_label: I18n.t("ui.nav.menu"),
          **@attrs
        ) do
          @destinations.each { |dest| dest.elevated ? elevated_tab(dest) : tab(dest) }
        end
      end

      private

      def tab(dest)
        active = dest.key == @active
        a(
          href: dest.href,
          aria_current: (active ? "page" : nil),
          class: [
            "flex flex-col items-center justify-center rounded-full px-4 py-1 transition",
            (active ? "bg-accent-sage text-page" : "text-muted active:bg-surface-container-high")
          ].join(" ")
        ) do
          render dest.icon.new(css: "h-6 w-6")
          span(class: "mt-1 text-label-caps uppercase") { I18n.t(dest.label_key) }
        end
      end

      # Elevated centre action (Scan) — floats above the bar.
      def elevated_tab(dest)
        a(
          href: dest.href,
          class: "relative flex flex-col items-center justify-center px-4 py-1 text-muted",
          aria_label: I18n.t(dest.label_key)
        ) do
          div(
            class: "absolute -top-6 flex h-14 w-14 items-center justify-center " \
                   "rounded-full border-4 border-card bg-accent-sage text-page"
          ) do
            render dest.icon.new(css: "h-6 w-6")
          end
          span(class: "mt-8 text-label-caps uppercase") { I18n.t(dest.label_key) }
        end
      end
    end
  end
end
