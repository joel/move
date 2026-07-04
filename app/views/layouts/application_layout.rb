# frozen_string_literal: true

module Views
  module Layouts
    class ApplicationLayout < Components::Base
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
            render Components::TopNav.new
            render_main(&)
          end
        end
      end

      private

      #: () ?{ (*untyped) -> untyped } -> untyped
      def render_main(&)
        main(class: "relative") do
          render_background_decorations
          div(class: "relative px-6 py-8 sm:px-10") do
            div(class: "mx-auto max-w-5xl ha-fade-in", &)
          end
        end
      end

      #: () -> untyped
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
    end
  end
end
