# frozen_string_literal: true

module Components
  module Ui
    # Responsive app shell: desktop sidebar + content (lg+), mobile top bar +
    # bottom tab bar. Applies the margin-mobile / margin-desktop rhythm and a
    # single-column mobile stack. Stateless in D0 (wired to Move context in D1).
    #
    #   render Components::Ui::AppLayout.new(active: :boxes) { content }
    class AppLayout < Components::Base
      def initialize(active: :boxes, **attrs)
        @active = active.to_sym
        @attrs = attrs
      end

      def view_template(&)
        div(class: "flex min-h-screen bg-page text-text-warm", **@attrs) do
          render Components::Ui::Sidebar.new(active: @active)
          mobile_top_bar
          main(
            class: "flex min-h-screen w-full flex-1 flex-col " \
                   "px-margin-mobile pb-32 pt-20 lg:ml-[280px] lg:px-margin-desktop lg:pb-10 lg:pt-10"
          ) do
            div(class: "mx-auto flex w-full max-w-5xl flex-col gap-section-gap", &)
          end
          render Components::Ui::BottomTabBar.new(active: @active)
        end
      end

      private

      def mobile_top_bar
        header(
          class: "lg:hidden fixed left-0 top-0 z-40 flex w-full items-center " \
                 "justify-between border-b border-card-border bg-page px-margin-mobile py-4"
        ) do
          span(class: "text-headline-md text-text-warm font-bold") { "Move" }
          button(
            type: "button",
            aria_label: I18n.t("ui.nav.account"),
            class: "text-accent-sage transition hover:opacity-80"
          ) do
            render Components::Icons::UserCircle.new(css: "h-7 w-7")
          end
        end
      end
    end
  end
end
