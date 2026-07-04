# frozen_string_literal: true

module Components
  class RodauthFlash < Components::Base
    include Phlex::Rails::Helpers::Flash

    #: () -> void
    def view_template
      return unless flash[:notice] || flash[:alert]

      if flash[:notice]
        div(
          class: "rounded-card border border-accent-sage/30 bg-accent-sage/15 " \
                 "px-4 py-3 text-body-md font-medium text-text-warm"
        ) { plain flash[:notice] }
      end

      return unless flash[:alert]

      div(
        class: "rounded-card border border-secondary/30 bg-secondary/15 " \
               "px-4 py-3 text-body-md font-medium text-text-warm"
      ) { plain flash[:alert] }
    end
  end
end
