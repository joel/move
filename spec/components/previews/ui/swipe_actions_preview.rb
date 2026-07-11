# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::SwipeActions (#602). The option
  # layers are lg:hidden and the swipe-actions controller no-ops at desktop
  # widths — narrow the preview window below lg (1024px) to try the gesture
  # (mouse drag works too).
  class SwipeActionsPreview < Lookbook::Preview
    # Swipe right → Edit (sage), swipe left → Remove (error).
    def default
      demo(id: "swipe-demo-default", name: "Glass backsplash",
           leading: ->(c) { edit_option(c) }, trailing: ->(c) { remove_option(c) })
    end

    def leading_only
      demo(id: "swipe-demo-leading", name: "Ceramic vase", leading: ->(c) { edit_option(c) })
    end

    def trailing_only
      demo(id: "swipe-demo-trailing", name: "Copper kettle", trailing: ->(c) { remove_option(c) })
    end

    private

    def demo(id:, name:, leading: nil, trailing: nil)
      render Components::Ui::SwipeActions.new(
        id:, leading:, trailing:,
        css: "rounded-card border border-card-border bg-card",
        content_css: "flex items-center gap-3 p-4"
      ) { |c| row_content(c, name) }
    end

    def row_content(row, name)
      row.div(class: "flex flex-1 flex-col gap-1") do
        row.span(class: "text-body-lg text-text-warm") { name }
        row.span(class: "text-label-caps uppercase text-muted") { "82% confidence" }
      end
    end

    def edit_option(row)
      row.button(
        type: "button", aria_label: "Edit item",
        data: { action: "swipe-actions#close" },
        class: "#{Components::Ui::SwipeActions::OPTION_CLASSES} bg-accent-sage/15 text-accent-sage"
      ) do
        row.render Components::Icons::Pencil.new(css: "h-5 w-5")
        row.span(class: "text-label-caps uppercase") { "Edit" }
      end
    end

    def remove_option(row)
      row.button(
        type: "button", aria_label: "Remove item",
        data: { action: "swipe-actions#close" },
        class: "#{Components::Ui::SwipeActions::OPTION_CLASSES} bg-error text-on-error"
      ) do
        row.render Components::Icons::Trash.new(css: "h-5 w-5")
        row.span(class: "text-label-caps uppercase") { "Remove" }
      end
    end
  end
end
