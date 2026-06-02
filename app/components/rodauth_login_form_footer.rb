# frozen_string_literal: true

module Components
  class RodauthLoginFormFooter < Components::Base
    include Phlex::Rails::Helpers::LinkTo

    def view_template
      return if view_context.rodauth.login_form_footer_links.empty?

      div(class: "mt-6 pt-6") do
        p(class: "ha-overline") do
          plain "More options"
        end
        div(class: "mt-2 flex flex-wrap gap-3 text-sm text-[var(--ha-muted)]") do
          view_context.rodauth.login_form_footer_links.sort.each do |_, link, text|
            link_to(text, link, class: "text-[var(--ha-text)] hover:underline")
          end
        end
      end
    end
  end
end
