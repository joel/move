# frozen_string_literal: true

module Views
  module Shared
    # Non-disclosing 404 — also shown for cross-org / unknown-subdomain access so
    # it never reveals whether a resource or Organization exists.
    class NotFound < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def view_template
        div(class: "mx-auto flex min-h-[60vh] max-w-xl flex-col items-center " \
                   "justify-center gap-4 text-center") do
          p(class: "text-label-caps uppercase text-muted") { "404" }
          h1(class: "text-headline-lg-mobile md:text-headline-lg text-text-warm") do
            plain t("errors.not_found.title")
          end
          p(class: "text-body-md text-on-surface-variant") do
            plain t("errors.not_found.description")
          end
          render Components::Ui::Button.new(
            label: t("errors.not_found.action"),
            href: view_context.root_path
          )
        end
      end
    end
  end
end
