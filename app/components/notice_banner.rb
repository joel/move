# frozen_string_literal: true

module Components
  class NoticeBanner < Components::Base
    def initialize(message:)
      @message = message
    end

    def view_template
      p(
        id: "notice",
        class: "ha-card border border-emerald-200 bg-emerald-50/80 px-4 py-3 text-sm " \
               "font-medium text-emerald-700 dark:border-emerald-500/30 dark:bg-emerald-500/10 " \
               "dark:text-emerald-200"
      ) { @message }
    end
  end
end
