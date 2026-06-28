# frozen_string_literal: true

module Components
  # A2 Boxes Home grid item. Reuses Ui::Card's micro-bar slot for the bottom
  # summary strip and Ui::ProgressBar for the packed indicator. Item counts and
  # recognition runs arrive in later phases (D5/D4); `recognition_state` is the
  # integration point — passed nil until D4 supplies runs.
  class BoxCard < Components::Base
    def initialize(box:, item_count: 0, recognition_state: nil, highlight: false)
      @box = box
      @item_count = item_count
      @recognition_state = recognition_state
      @highlight = highlight
    end

    def view_template
      a(href: move_box_path(@box.move_id, @box), class: link_classes) do
        render Components::Ui::Card.new(interactive: true, micro_bar: micro_bar) do
          header_row
          title_block
        end
      end
    end

    private

    # `rounded-card` so the one-time highlight ring (a box-shadow) follows the
    # card's shape when this is the just-created box (#336).
    def link_classes
      base = "block rounded-card"
      @highlight ? "#{base} box-added-highlight" : base
    end

    def header_row
      div(class: "flex items-start justify-between gap-3") do
        div(
          class: "flex h-12 w-12 items-center justify-center rounded-full " \
                 "bg-surface-container-high text-accent-sage"
        ) { render Components::Icons::Boxes.new(css: "h-6 w-6") }

        div(class: "flex flex-col items-end gap-1.5") do
          if @recognition_state
            render Components::Ui::RecognitionState.new(state: @recognition_state)
          else
            span(class: badge_classes) { badge_label }
          end
          fragile_chip if @box.fragile?
        end
      end
    end

    # Fragile mark (Phase A) — error-tinted, matching the box header chip and the
    # FRAGILE mark printed on the box label.
    def fragile_chip
      span(class: "inline-flex items-center gap-1 rounded-full bg-error/15 px-2.5 py-1 " \
                  "text-label-caps uppercase text-error") do
        render Components::Icons::Alert.new(css: "h-3.5 w-3.5")
        span { I18n.t("boxes.fragile_badge") }
      end
    end

    def title_block
      div do
        h3(class: "mb-1 text-headline-md text-text-warm") { title }
        p(class: "text-body-md text-muted") { items_label }
      end
    end

    def items_label
      @item_count.zero? ? I18n.t("boxes.card.no_items") : I18n.t("boxes.card.items", count: @item_count)
    end

    # Bottom strip: status + items placeholder, the packed progress bar, and a
    # terracotta warning when dimensions are missing.
    def micro_bar
      box = @box
      lambda do |card|
        card.div(class: "flex justify-between text-label-caps uppercase text-muted") do
          card.span { status_label }
          card.span { items_label }
        end
        card.render Components::Ui::ProgressBar.new(value: box.packed? ? 100 : 0, max: 100)
        next unless box.missing_dimensions?

        card.div(class: "flex items-center gap-1.5 text-label-caps uppercase text-secondary") do
          card.render Components::Icons::Alert.new(css: "h-4 w-4")
          card.span { I18n.t("boxes.card.missing_dimensions") }
        end
      end
    end

    def title
      @box.room&.name.presence || I18n.t("boxes.card.no_room")
    end

    def badge_label
      # Kernel.format (not bare `format`, which is a Phlex element helper).
      I18n.t("boxes.card.badge", number: Kernel.format("%02d", @box.number.to_i))
    end

    def badge_classes
      "rounded-full bg-surface-container-high px-3 py-1 text-label-caps uppercase text-muted"
    end

    def status_label
      I18n.t("boxes.status.#{@box.status}", default: @box.status.titleize)
    end
  end
end
