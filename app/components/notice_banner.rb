# frozen_string_literal: true

module Components
  class NoticeBanner < Components::Base
    def initialize(message:)
      @message = message
    end

    def view_template
      p(
        id: "notice",
        class: "rounded-card border border-accent-sage/30 bg-accent-sage/15 px-4 py-3 " \
               "text-body-md font-medium text-text-warm"
      ) { @message }
    end
  end
end
