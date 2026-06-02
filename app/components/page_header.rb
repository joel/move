# frozen_string_literal: true

module Components
  class PageHeader < Components::Base
    def initialize(section:, title:, subtitle: nil)
      @section = section
      @title = title
      @subtitle = subtitle
    end

    def view_template(&block)
      div(class: "flex flex-col gap-4 sm:flex-row sm:items-end " \
                 "sm:justify-between") do
        div do
          p(class: "ha-overline") { @section }
          h1(class: "mt-2 font-headline text-4xl font-bold " \
                    "tracking-tighter md:text-5xl") { @title }
          if @subtitle
            p(class: "mt-2 text-sm text-[var(--ha-on-surface-variant)]") do
              plain @subtitle
            end
          end
        end
        div(class: "flex flex-wrap gap-3", &block) if block
      end
    end
  end
end
