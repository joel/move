# frozen_string_literal: true

module Components
  module Ui
    # Calm empty state: a soft icon medallion, a title, a description, and an
    # optional action slot (block). Falls back to I18n copy.
    #
    #   render Components::Ui::EmptyState.new(icon: Components::Icons::Boxes,
    #                                         title: "No boxes yet")
    class EmptyState < Components::Base
      #: (?icon: untyped, ?title: untyped, ?description: untyped, **untyped) -> void
      def initialize(icon: Components::Icons::Boxes, title: nil, description: nil, **attrs)
        @icon = icon
        @title = title || I18n.t("ui.empty.title")
        @description = description || I18n.t("ui.empty.description")
        @attrs = attrs
      end

      #: () ?{ (*untyped) -> untyped } -> untyped
      def view_template(&block)
        div(
          class: "flex flex-col items-center gap-4 rounded-card border " \
                 "border-card-border bg-card px-6 py-12 text-center",
          **@attrs
        ) do
          div(
            class: "flex h-16 w-16 items-center justify-center rounded-full " \
                   "bg-surface-container-high text-muted"
          ) do
            render @icon.new(css: "h-7 w-7")
          end
          h3(class: "text-headline-md text-text-warm") { @title }
          p(class: "max-w-sm text-body-md text-on-surface-variant") { @description }
          div(class: "mt-2 flex flex-wrap justify-center gap-3", &block) if block
        end
      end
    end
  end
end
