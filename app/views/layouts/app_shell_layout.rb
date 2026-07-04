# frozen_string_literal: true

module Views
  module Layouts
    # Page layout for the in-app surfaces that use the D0 responsive shell
    # (desktop sidebar + mobile bottom tab bar) — Boxes Home and the screens that
    # follow it. Shares <head>/theme/flash with ApplicationLayout but swaps the
    # TopNav + centred container for Components::Ui::AppLayout.
    class AppShellLayout < Components::Base
      include Phlex::Rails::Layout
      include ChromeHead

      #: () ?{ (*untyped) -> untyped } -> untyped
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
            render(Components::Ui::AppLayout.new, &)
          end
        end
      end
    end
  end
end
