# frozen_string_literal: true

module Components
  class RodauthFlash < Components::Base
    include Phlex::Rails::Helpers::Flash

    def view_template
      return unless flash[:notice] || flash[:alert]

      if flash[:notice]
        div(
          class: "ha-card border border-emerald-200 bg-emerald-50/80 px-4 py-3 text-sm " \
                 "font-medium text-emerald-700 dark:border-emerald-500/30 " \
                 "dark:bg-emerald-500/10 dark:text-emerald-200"
        ) { plain flash[:notice] }
      end

      return unless flash[:alert]

      div(
        class: "ha-card bg-[var(--ha-error-container)] px-4 py-3 text-sm " \
               "font-medium text-[var(--ha-error)]"
      ) { plain flash[:alert] }
    end
  end
end
